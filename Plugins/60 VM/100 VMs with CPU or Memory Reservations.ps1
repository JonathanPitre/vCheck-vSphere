$Title = "VMs with CPU or Memory Reservations Configured"
$Header = "VMs with CPU or Memory Reservations Configured: [count]"
$Comments = "The following VMs have a CPU or Memory Reservation configured which may impact the performance of the VM. Note: -1 indicates no reservation"
$Display = "Table"
$Author = "Dan Jellesma and Jonathan Pitre"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings
# Do not report on any VMs who are defined here
$MCRDoNotInclude = ""
# End of Settings

# Update settings where there is an override
$MCRDoNotInclude = Get-vCheckSetting $Title "MCRDoNotInclude" $MCRDoNotInclude

$FullVM |
Where-Object {
    $_.Name -notmatch $MCRDoNotInclude -and (
        [double]($_.ExtensionData.ResourceConfig.CpuAllocation.Reservation) -gt 0 -or
        [double]($_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation) -gt 0
    )
} |
Select-Object Name,
@{Name = "CPUReservationMhz"; E = { $_.ExtensionData.ResourceConfig.CpuAllocation.Reservation } },
@{Name = "MemReservationMB"; E = { $_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation } }

# Change Log
## 1.0 : Initial Release
## 1.1 : Added Get-vCheckSetting
## 1.2 : Use ExtensionData.ResourceConfig* reservations (vSphere 8 compatible) and treat null as 0
## 1.3 : Replace null-coalescing (??) with PowerShell 5-compatible casting