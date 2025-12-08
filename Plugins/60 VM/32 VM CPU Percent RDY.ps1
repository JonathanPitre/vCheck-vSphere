$Title = "VM CPU %RDY"
$Comments = "The following VMs have high CPU RDY times, this can cause performance issues. For more information see <a href='https://knowledge.broadcom.com/external/article/387750' target='_blank'>Understanding the CPU Ready values in the vSphere Client</a> and <a href='https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-performance/index.html' target='_blank'>Performance Best Practices for VMware vSphere 8.0</a>"
$Display = "Table"
$Author = "Alan Renouf and Jonathan Pitre"
$PluginVersion = 1.4
$PluginCategory = "vSphere"

# Start of Settings 
# CPU ready on VMs should not exceed
$PercCPUReady = 5.0
# End of Settings

# Setup plugin-specific language table
$pLang = DATA {
   ConvertFrom-StringData @' 
      pluginActivity = Checking VM CPU RDY %
'@
}

# Override the default (en) if it exists in lang directory
Import-LocalizedData -BaseDirectory ($ScriptPath + "\Lang") -BindingVariable pLang -ErrorAction SilentlyContinue

# Update settings where there is an override
$PercCPUReady = Get-vCheckSetting $Title "PercCPUReady" $PercCPUReady

$i = 0
ForEach ($v in ($VM | Where-Object { $_.PowerState -eq "PoweredOn" })) {
   Write-Progress -ID 2 -Parent 1 -Activity $plang.pluginActivity -Status $v.Name -PercentComplete ((100 * $i) / $VM.Count)
   For ($cpunum = 0; $cpunum -lt $v.NumCpu; $cpunum++) {
      $samples = $v | Get-Stat -ErrorAction SilentlyContinue -Stat cpu.ready.summation -Realtime -MaxSamples 18 | Where-Object { $_.Instance -eq $cpunum }
      if ($samples) {
         $avgReadyMs = ($samples | Measure-Object -Property Value -Average).Average
         $intervalSec = ($samples | Select-Object -First 1 -ExpandProperty IntervalSecs)
         if (-not $intervalSec -or $intervalSec -eq 0) { $intervalSec = 20 } # default realtime rollup
         $PercReady = [Math]::Round(($avgReadyMs / ($intervalSec * 10)), 1) # ms over interval -> percent
         
         if ($PercReady -gt $PercCPUReady) {
            New-Object -TypeName PSObject -Property @{
               VM        = $v.Name
               VMHost    = $v.VMHost
               CPU       = $cpunum
               PercReady = $PercReady
            }
         }
      }
   }
   $i++
}
Write-Progress -ID 2 -Parent 1 -Activity $plang.pluginActivity -Status $lang.Complete -Completed

$Header = ("VM CPU % RDY over {0}: [count]" -f $PercCPUReady)

# Change Log
## 1.2 :  Added Get-vCheckSetting, code refactor
## 1.3 : Updated broken documentation link to official Broadcom Knowledge Base article and Performance Best Practices guide
## 1.4 : Fix CPU ready calculation to use actual sample interval (vSphere 8 realtime), add MaxSamples
