$Title = "VM Tools Issues"
$Header = "VM Tools Issues: [count]"
$Comments = "Powered-on VMs where VMware Tools is present but not reporting key guest details (name/IP/hostname/disk/net). Indicates broken/stale Tools or guest reporting issues."
$Display = "Table"
$Author = "Alan Renouf and Jonathan Pitre"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings 
# VM Tools Issues, do not report on any VMs who are defined here
$VMTDoNotInclude = ""
# End of Settings

# Update settings where there is an override
$VMTDoNotInclude = Get-vCheckSetting $Title "VMTDoNotInclude" $VMTDoNotInclude

$FullVM |
Where-Object {
    $_.Name -notmatch $VMTDoNotInclude -and
    $_.Guest.GuestState -eq "Running" -and
    (
        $_.Guest.GuestFullName -eq $null -or
        $_.Guest.IPAddress -eq $null -or
        $_.Guest.HostName -eq $null -or
        $_.Guest.Disk -eq $null -or
        $_.Guest.Net -eq $null
    )
} |
Select-Object Name,
@{N = "IPAddress"; E = { if ($_.Guest.IPAddress) { $_.Guest.IPAddress[0] } else { $null } } },
@{N = "OSFullName"; E = { $_.Guest.GuestFullName } },
@{N = "HostName"; E = { $_.Guest.HostName } },
@{N = "NetworkLabel"; E = { if ($_.Guest.Net -and $_.Guest.Net[0]) { $_.Guest.Net[0].Network } else { $null } } } |
Sort-Object Name

# Change Log
## 1.2 : Added Get-vCheckSetting
## 1.3 : Safer guest data extraction (vSphere 8 U2+), clarified description