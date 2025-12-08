# This plugin checks for Spectre vulnerability mitigations in VMs.
# It checks for the following mitigations:
# - IBRS (Indirect Branch Restricted Speculation)
# - IBPB (Indirect Branch Prediction Barrier)
# - STIBP (Speculative Trap-to-User-Mode Instruction Fetch Barrier)
# - SSBD (Speculative Store Bypass Disable)
# It also checks if the VM is running on a host that supports the necessary CPUID bits.
# See <a href='https://knowledge.broadcom.com/external/article?legacyId=52085' target='_blank'>Broadcom KB 52085</a> for more information.

$result = @()
foreach ($vmobj in $FullVM | Sort-Object -Property Name) {
    # Only check VMs that are powered on
    if ($vmobj.Runtime.PowerState -eq "poweredOn") {
        $vmDisplayName = $vmobj.Name
        $vmvHW = $vmobj.Config.Version
        $vmHwNumber = 0
        [void][int]::TryParse(($vmvHW -replace "vmx-", ""), [ref]$vmHwNumber)

        # Hardware version check: <9 cannot expose the necessary CPUID bits -> mark as legacy (N/A)
        $hwSupportsSpectreBits = ($vmHwNumber -ge 9)

        $IBRSPass  = $false
        $IBPBPass  = $false
        $STIBPPass = $false
        $SSBDPass  = $false  # Speculative Store Bypass Disable (some CPUs expose this)

        $cpuFeatures = $vmobj.Runtime.FeatureRequirement
        foreach ($cpuFeature in $cpuFeatures) {
            switch ($cpuFeature.Key) {
                "cpuid.IBRS"   { $IBRSPass = $true; break }
                "cpuid.IBPB"   { $IBPBPass = $true; break }
                "cpuid.STIBP"  { $STIBPPass = $true; break }
                "cpuid.SSBD"   { $SSBDPass = $true; break }
                "cpuid.SSB_NO" { $SSBDPass = $true; break }
            }
        }

        $featurePass = ($IBRSPass -or $IBPBPass -or $STIBPPass -or $SSBDPass)
        $vmAffected = if (-not $hwSupportsSpectreBits) {
            "N/A" # legacy vHW cannot expose mitigation bits; upgrade vHW
        } elseif ($featurePass) {
            $false
        } else {
            $true
        }

        $tmp = [pscustomobject] @{
            VM          = $vmDisplayName
            IBRPresent  = $IBRSPass
            IBPBPresent = $IBPBPass
            STIBPresent = $STIBPPass
            SSBPresent  = $SSBDPass
            vHW         = $vmvHW
            Affected    = $vmAffected
        }
        $result += $tmp
    }
}
# Filter to only show affected VMs (true) or legacy hardware (N/A requires vHW upgrade)
$Result = $result | Where-Object { $_.Affected -eq $true -or $_.Affected -eq "N/A" }
$Result

$Title = "VMs Exposed to Spectre Vulnerability"
$Header = "Virtual Machines Exposed to Spectre Vulnerability: $(@($Result).Count)"
$Comments = "Powered-on VMs lacking Spectre v2 mitigation bits (IBRS/IBPB/STIBP/SSBD). Legacy vHW (<9) is marked N/A because it cannot expose the CPUID bits—upgrade vHW then ensure mitigations are enabled. See <a href='https://knowledge.broadcom.com/external/article?legacyId=52085' target='_blank'>Broadcom KB 52085</a> and <a href='https://www.virtuallyghetto.com/2018/01/how-to-verify-spectre-meltdown-mitigation-in-a-vm.html' target='_blank'>Virtually Ghetto guide</a>."
$Display = "Table"
$Author = "William Lam"
$PluginVersion = 1.5
$PluginCategory = "vSphere"

# Changelog
## 1.0 : Initial version.
## 1.2 : The variable $vm has been changed to $vmobj because $vm is defined globally. This modification allows subsequent plugins to run without problems.
## 1.3 : Treat vHW >= 9 as capable; only flag VMs missing IBRS/IBPB/STIBP. Older vHW reported as N/A.
## 1.4 : Add SSBD/SSB_NO detection (Spectre v2 SSB mitigation) and include KB 317619 reference.
## 1.5 : Fix Affected calculation to only mark N/A for legacy vHW (<9); add SSBD/SSB_NO detection, safer parsing, and updated comments.
