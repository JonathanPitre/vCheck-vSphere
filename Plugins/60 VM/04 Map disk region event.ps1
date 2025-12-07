$Title = "Map disk region event"
$Comments = "These events may occur during virtual machine backups, especially when using SAN transport mode with large or fragmented VMDK files. This can cause performance issues or make vCenter Server unresponsive. Check <a href='https://knowledge.broadcom.com/external/article?legacyId=2148199' target='_blank'>KB 2148199</a> for more details. Fixed in vCenter Server 6.0 Update 3 and later."
$Display = "Table"
$Author = "Alan Renouf, Jonathan Pitre"
$PluginVersion = 1.4
$PluginCategory = "vSphere"

# Check if applicable
if ([version]($global:DefaultVIServer.Version) -le [version]"5.0") {
    # Start of Settings 
    # Set the number of days to show Map disk region event for
    $eventAge = 5
    # End of Settings 
    
    # Update settings where there is an override
    $eventAge = Get-vCheckSetting $Title "eventAge" $eventAge
    
    Get-VIEventPlus -Start ($Date).AddDays(-$eventAge) -Type Info | Where-Object { $_.FullFormattedMessage -match "Map disk region" } | Foreach-Object { $_.vm } | Select-Object name | Sort-Object -unique
    
    $Header = ("Map disk region event (Last {0} Day(s)): [count]" -f $eventAge)
} else {
    $Header = ("KB not applicable - vCenter version {0}" -f $global:DefaultVIServer.Version)
}
    
# Change Log
## 1.3 : Added test if KB1007331 is applicable (vCenter 5 and lower)
## 1.2 : Added Get-vCheckSetting and Get-VIEventPlus
## 1.4 : Updated KB article link to valid Broadcom KB article (KB 2148199). Updated description to reflect that issue is fixed in vCenter 6.0 Update 3 and later.