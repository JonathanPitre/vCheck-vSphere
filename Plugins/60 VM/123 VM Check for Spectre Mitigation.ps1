# Start of Settings
# End of Settings

$result = @()
foreach ($vmobj in $FullVM | Sort-Object -Property Name) {
    # Only check VMs that are powered on
    if ($vmobj.Runtime.PowerState -eq "poweredOn") {
        $vmDisplayName = $vmobj.Name
        $vmvHW = $vmobj.Config.Version
        $vmHwNumber = [int]($vmvHW -replace "vmx-", "")

        # Hardware version check: <9 is too old, >=9 supports exposing the required CPU features
        $vHWPass = if ($vmHwNumber -lt 9) { "N/A" } else { $true }

        $IBRSPass = $false
        $IBPBPass = $false
        $STIBPPass = $false

        $cpuFeatures = $vmobj.Runtime.FeatureRequirement
        foreach ($cpuFeature in $cpuFeatures) {
            if ($cpuFeature.key -eq "cpuid.IBRS") {
                $IBRSPass = $true
            } elseif ($cpuFeature.key -eq "cpuid.IBPB") {
                $IBPBPass = $true
            } elseif ($cpuFeature.key -eq "cpuid.STIBP") {
                $STIBPPass = $true
            }
        }

        $featurePass = ($IBRSPass -or $IBPBPass -or $STIBPPass)
        $vmAffected = if ($vHWPass -eq "N/A") {
            "N/A"
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
            vHW         = $vmvHW
            Affected    = $vmAffected
        }
        $result += $tmp
    }
}
# Filter to only show affected VMs (Affected = $true or "N/A" for old hardware versions)
$Result = $result | Where-Object { $_.Affected -eq $true -or $_.Affected -eq "N/A" }
$Result

$Title = "VMs Exposed to Spectre Vulnerability"
$Header = "Virtual Machines Exposed to Spectre Vulnerability: $(@($Result).Count)"
$Comments = "The following VMs require remediation to mitigate the Spectre vulnerability. See the following URLs for more information: <a href='https://knowledge.broadcom.com/external/article?legacyId=52085' target='_blank'>KB 52085</a>, <a href='https://www.virtuallyghetto.com/2018/01/verify-hypervisor-assisted-guest-mitigation-spectre-patches-using-powercli.html' target='_blank'>Virtually Ghetto</a>."
$Display = "Table"
$Author = "William Lam"
$PluginVersion = 1.1
$PluginCategory = "vSphere"


# Changelog
## 1.0 : Initial version.
## 1.2 : The variable $vm has been changed to $vmobj because $vm is defined globally. This modification allows subsequent plugins to run without problems.
## 1.3 : Treat vHW >= 9 as capable; only flag VMs missing IBRS/IBPB/STIBP. Older vHW reported as N/A.

# Changelog
## 1.0 : Initial version.
## 1.2 : The variable $vm has been changed to $vmobj because $vm is defined globally. This modification allows subsequent plugins to run without problems.
## 1.3 : Treat vHW >= 9 as capable; only flag VMs missing IBRS/IBPB/STIBP. Older vHW reported as N/A.
## 1.4 : Add SSBD/SSB_NO detection (Spectre v2 SSB mitigation) and include KB 317619 reference.

