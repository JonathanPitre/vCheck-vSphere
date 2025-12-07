# Start of Settings 
# Set the warning threshold for snapshots in days old (VMware recommends not keeping snapshots for more than 72 hours/3 days)
$SnapshotAge = 3
# Maximum recommended snapshot depth (VMware recommends max 2-3 snapshots per VM)
$MaxSnapshotDepth = 3
# Set snapshot name exception (regex)
$ExcludeName = "^(ExcludeMe|ExcludeMeToo)$"
# Set snapshot creator exception (regex)
$ExcludeCreator = "^(ExcludeMe|ExcludeMeToo)$"
# End of Settings

Add-Type -AssemblyName System.Web
$Output = @()

# Function to calculate snapshot depth
function Get-SnapshotDepth {
    param($Snapshot)
    $depth = 0
    $current = $Snapshot
    while ($current.ParentSnapshot) {
        $depth++
        $current = $current.ParentSnapshot
    }
    return $depth
}

# Check for snapshots over age threshold or exceeding depth
foreach ($vmObj in $VM) {
    $snapshots = $vmObj | Get-Snapshot
    if ($snapshots) {
        foreach ($Snapshot in $snapshots) {
            if ($Snapshot.Name -match $ExcludeName) {
                continue
            }
            
            $snapshotAge = ((Get-Date) - $Snapshot.Created).Days
            $snapshotDepth = Get-SnapshotDepth -Snapshot $Snapshot
            $isOld = $snapshotAge -ge $SnapshotAge
            $isTooDeep = $snapshotDepth -ge $MaxSnapshotDepth
            
            # Report if snapshot is too old OR exceeds depth limit
            if ($isOld -or $isTooDeep) {
                # This little +/-1 minute time span is a small buffer in case of time differences between the vCenter and the reporting server. This might cause wrong
                # results in the uncommon case of two different people creating a snapshot for the same VM within two minutes. In this scenario the wrong creator will be
                # displayed but nevertheless this approach shows every existing snapshot. Usage of Get-VIEventPlus in the style of "85 Snapshot Activity.ps1".
                $SnapshotEvents = Get-VIEventPlus -Entity $vmObj -EventType "TaskEvent" -Start $Snapshot.Created.AddMinutes(-1) -Finish $Snapshot.Created.AddMinutes(1)
                $SnapshotEvent = $SnapshotEvents | Where-Object { $_.Info.DescriptionId -eq "VirtualMachine.createSnapshot" } | Select-Object -First 1

                if ($SnapshotEvent -eq $null) {
                    $SnapshotCreator = "Unknown"
                } elseif ($SnapshotEvent.UserName -match $ExcludeCreator) {
                    # This is the earliest point where I can neglect snapshots from certain creators
                    continue
                } else {
                    $SnapshotCreator = $SnapshotEvent.UserName
                }

                $Output += [PSCustomObject]@{
                    VM          = $vmObj.Name
                    SnapName    = [System.Web.HttpUtility]::HtmlEncode($Snapshot.Name)
                    DaysOld     = $snapshotAge
                    Depth       = $snapshotDepth
                    Creator     = $SnapshotCreator
                    SizeGB      = $Snapshot.SizeGB.ToString("f1")
                    Created     = $Snapshot.Created.DateTime
                    Description = [System.Web.HttpUtility]::HtmlEncode($Snapshot.Description)
                    Issue       = if ($isOld -and $isTooDeep) { "Age & Depth" } elseif ($isOld) { "Age" } else { "Depth" }
                }
            }
        }
    }
}

# Output result
$Output

$Title = "Snapshot Information"
$Header = "Snapshots (Over $SnapshotAge Days Old or Depth > $MaxSnapshotDepth): [count]"
$Comments = "VMware snapshots which are kept for a long period of time may cause issues, filling up datastores and also may impact performance of the virtual machine. VMware recommends not keeping snapshots for more than 72 hours (3 days) and limiting snapshot depth to 2-3 snapshots per VM. For details see <a href='https://www.vmware.com/content/dam/digitalmarketing/vmware/en/pdf/techpaper/performance/vsphere-vm-snapshots-perf.pdf' target='_blank'>VMware vSphere Virtual Machine Snapshots Performance</a>."
$Display = "Table"
$Author = "Alan Renouf, Raphael Schitz, Marcel Schuster"
$PluginVersion = 1.7
$PluginCategory = "vSphere"

# Changelog
## 1.3 : Cleanup - Fixed Creator - Changed Size to GB
## 1.4 : Decode URL-encoded snapshot name (i.e. the %xx caharacters)
## 1.5 : ???
## 1.6 : Complete restructuring because of missing creator names. Also removed $excludeDesc.
## 1.7 : Updated default age threshold from 14 to 3 days (VMware best practice), added snapshot depth checking (max 3), added documentation link, and added Issue column to identify age vs depth violations.
