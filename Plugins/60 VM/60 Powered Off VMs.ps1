$Title = "Powered Off VMs"
$Header = "VMs Powered Off - Number of Days"
$Display = "Table"
$Author = "Adam Schwartzberg, Fabio Freire"
$PluginVersion = 1.7
$PluginCategory = "vSphere"

# Start of Settings
# VMs not to report on (regex)
$IgnoredVMs = "TEMPLATE|BUILD"
# VmPathName not to report on
$IgnoredVMpath = "-backup-"
# VmFolder not to report on
$IgnoredVMFolder = "Templates"
# Report VMs powered off over this many days
$PoweredOffDays = 7
# End of Settings

# Update settings where there is an override
$IgnoredVMs = Get-vCheckSetting $Title "IgnoredVMs" $IgnoredVMs
$IgnoredVMpath = Get-vCheckSetting $Title "IgnoredVMpath" $IgnoredVMpath
$PoweredOffDays = Get-vCheckSetting $Title "PoweredOffDays" $PoweredOffDays

# Filter VMs first using cheap properties to avoid expensive LastPoweredOffDate queries
# This prevents memory issues when there are many powered-off VMs
$filteredVMs = $VM | Where-Object {
    $_.ExtensionData.Config.ManagedBy.ExtensionKey -ne 'com.vmware.vcDr' -and
    $_.PowerState -eq "PoweredOff" -and
    $_.Name -notmatch $IgnoredVMs -and
    $_.Folder.Name -notmatch $IgnoredVMFolder -and
    $_.ExtensionData.Config.Files.VmPathName -notmatch $IgnoredVMpath
}

# Now check LastPoweredOffDate only for filtered VMs to minimize expensive event queries
$results = @()
foreach ($vm in $filteredVMs) {
    try {
        $lastPoweredOffDate = $vm.LastPoweredOffDate
        if ($lastPoweredOffDate -and $lastPoweredOffDate -lt $date.AddDays(-$PoweredOffDays)) {
            $results += [PSCustomObject]@{
                Name = $vm.Name
                LastPoweredOffDate = $lastPoweredOffDate
                Folder = $vm.Folder.Name
                Notes = $vm.Notes
            }
        }
    }
    catch {
        # Skip VMs where LastPoweredOffDate query fails to prevent script failure
        Write-Verbose "Could not get LastPoweredOffDate for VM $($vm.Name): $_"
    }
}

# Output sorted results
$results | Sort-Object -Property LastPoweredOffDate

$Comments = ("May want to consider deleting VMs that have been powered off for more than {0} days" -f $PoweredOffDays)

# Change Log
## 1.4 : Added Get-vCheckSetting, $PoweredOffDays
## 1.5 : Select-Object now returns Folder as a string; Added IgnoredVMpath
## 1.6 : Added IgnoredVMFolder
## 1.7 : Fixed memory issue by filtering VMs first, then checking LastPoweredOffDate only for filtered VMs (Issue #765)
