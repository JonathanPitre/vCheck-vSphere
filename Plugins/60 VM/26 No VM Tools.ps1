$Title = "No VM Tools"
$Header = "No VM Tools: [count]"
$Comments = "Powered-on VMs where VMware Tools is not installed or not running. Tools are required for optimized drivers (VMXNET3/PVSCSI), graceful ops, and performance."
$Display = "Table"
$Author = "Alan Renouf and Jonathan Pitre"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings
# Do not report on any VMs who are defined here (regex)
$VMTDoNotInclude = ""
# End of Settings

# Update settings where there is an override
$VMTDoNotInclude = Get-vCheckSetting $Title "VMTDoNotInclude" $VMTDoNotInclude

# vSphere 8.x uses ToolsVersionStatus2; fall back to ToolsVersionStatus if needed
$noToolsStatuses = @("guestToolsNotInstalled", "guestToolsNotRunning")

$FullVM |
Where-Object {
    $_.Name -notmatch $VMTDoNotInclude -and
    $_.Runtime.PowerState -eq "poweredOn" -and
    ($noToolsStatuses -contains ($_.ExtensionData.Guest.ToolsVersionStatus2 ?? $_.ExtensionData.Guest.ToolsVersionStatus))
} |
Select-Object Name,
@{N = "Status"; E = { $_.ExtensionData.Guest.ToolsVersionStatus2 ?? $_.ExtensionData.Guest.ToolsVersionStatus } },
@{N = "RunningStatus"; E = { $_.ExtensionData.Guest.ToolsRunningStatus } }

# Change Log
## 1.2 : Added Get-vCheckSetting
## 1.3 : Use ToolsVersionStatus2 with fallback, include RunningStatus, vSphere 8 U2+ compatible