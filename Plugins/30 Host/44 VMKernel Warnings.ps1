$Title = "VMKernel Warnings"
$Header = "ESX/ESXi VMKernel Warnings: [count]"
$Comments = "The following VMKernel issues were found, it is suggested all unknown issues are explored on the VMware Knowledge Base and vSphere documentation. Use the below links to automatically search for the string"
$Display = "Table"
$Author = "Alan Renouf, Frederic Martin"
$PluginVersion = 1.4
$PluginCategory = "vSphere"

# Start of Settings
# Disabling displaying Google/KB/vSphere documentation links in order to have wider message column
$simpleWarning = $true
# End of Settings

# Update settings where there is an override
$simpleWarning = Get-vCheckSetting $Title "simpleWarning" $simpleWarning

$VMKernelWarnings = @()
foreach ($VMHost in ($HostsViews)) {
   $product = $VMHost.config.product.ProductLineId
   if ($product -eq "embeddedEsx" -and $VIVersion -lt 5) {
      $Warnings = (Get-Log -vmhost ($VMHost.name) -Key messages -ErrorAction SilentlyContinue).entries | Where-Object { $_ -match "warning" -and $_ -match "vmkernel" }
      if ($Warnings -ne $null) {
         $VMKernelWarning = @()
         $Warnings | % {
            if ($simpleWarning) {
               $Details = "" | Select-Object VMHost, Message
               $Details.VMHost = $VMHost.Name
               $Details.Message = $_
            } else {
               $Details = "" | Select-Object VMHost, Message, Length, KBSearch, Google, vSphereDocs
               $Details.VMHost = $VMHost.Name
               $Details.Message = $_
               $Details.Length = ($Details.Message).Length
               $MessageEncoded = [System.Uri]::EscapeDataString($Details.Message)
               $Details.KBSearch = "<a href='http://kb.vmware.com/selfservice/microsites/search.do?searchString=$MessageEncoded&sortByOverride=PUBLISHEDDATE&sortOrder=-1' target='_blank'>Click Here</a>"
               $Details.Google = "<a href='http://www.google.co.uk/search?q=$MessageEncoded' target='_blank'>Click Here</a>"
               $Details.vSphereDocs = "<a href='https://www.vmware.com/docs/vsphere-esxi-vcenter-server-80-troubleshooting-guide' target='_blank'>vSphere 8.0 Troubleshooting</a>"
            }
            $VMKernelWarning += $Details
         }
         $VMKernelWarnings += $VMKernelWarning | Sort-Object -Property Length -Unique | Select-Object VMHost, Message, KBSearch, Google, vSphereDocs
      }	
   } else {
      $Warnings = (Get-Log -VMHost ($VMHost.Name) -Key vmkernel -ErrorAction SilentlyContinue).Entries | Where-Object { $_ -match "warning" }
      if ($Warnings -ne $null) {
         $VMKernelWarning = @()
         $Warnings | Foreach-Object {
            if ($simpleWarning) {
               $Details = "" | Select-Object VMHost, Message
               $Details.VMHost = $VMHost.Name
               $Details.Message = $_
            } else {
               $Details = "" | Select-Object VMHost, Message, Length, KBSearch, Google, vSphereDocs
               $Details.VMHost = $VMHost.Name
               $Details.Message = $_
               $Details.Length = ($Details.Message).Length
               $MessageEncoded = [System.Uri]::EscapeDataString($Details.Message)
               $Details.KBSearch = "<a href='http://kb.vmware.com/selfservice/microsites/search.do?searchString=$MessageEncoded&sortByOverride=PUBLISHEDDATE&sortOrder=-1' target='_blank'>Click Here</a>"
               $Details.Google = "<a href='http://www.google.co.uk/search?q=$MessageEncoded' target='_blank'>Click Here</a>"
               $Details.vSphereDocs = "<a href='https://www.vmware.com/docs/vsphere-esxi-vcenter-server-80-troubleshooting-guide' target='_blank'>vSphere 8.0 Troubleshooting</a>"
            }
            $VMKernelWarning += $Details
         }
         $VMKernelWarnings += $VMKernelWarning | Sort-Object -Property Length -Unique | Select-Object VMHost, Message, KBSearch, Google, vSphereDocs
      }
   }
}

$VMKernelWarnings | Sort-Object Message -Descending