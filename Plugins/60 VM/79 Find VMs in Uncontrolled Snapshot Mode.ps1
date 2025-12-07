#region Internationalization
################################################################################
#                             Internationalization                             #
################################################################################
# Default language en-US
Import-LocalizedData -BaseDirectory ($ScriptPath + '\Lang') -BindingVariable pLang -UICulture en-US -ErrorAction SilentlyContinue

# Override the default (en-US) if it exists in lang directory
Import-LocalizedData -BaseDirectory ($ScriptPath + "\Lang") -BindingVariable pLang -ErrorAction SilentlyContinue

#endregion Internationalization

$Title = "VMs in uncontrolled snapshot mode"
$Header = "VMs in uncontrolled snapshot mode: [count]"
$Comments = "The following VMs are in snapshot mode, but vCenter isn't aware of it. See <a href='https://knowledge.broadcom.com/external/article?legacyId=1002310' target='_blank'>KB 1002310</a>"
$Display = "Table"
$Author = "Rick Glover, Matthias Koehler, Dan Rowe, Bill Wall, Legion87"
$PluginVersion = 1.8
$PluginCategory = "vSphere"

# Start of Settings
# Do not report uncontrolled snapshots on VMs that are defined here
$ExcludeDS = "ExcludeMe"
# Exception for specific file patterns (e.g., Xen-Desktop: "-xd-|-ctk.")
$ExceptionFP = ""
# End of Settings

# Variables for the results
$vmdks = @()
$items = @()

$i = 0
$datastoresToProcess = $Datastores | Where-Object { $_.Name -notmatch $ExcludeDS -and $_.State -eq "Available" }
foreach ($Datastore in $datastoresToProcess) {
    Write-Progress -ID 2 -Parent 1 -Activity $pLang.pluginActivity -Status ($pLang.pluginStatus -f $i, $datastoresToProcess.count, $Datastore.Name) -PercentComplete ($i * 100 / $datastoresToProcess.count)

    $DatastoreBrowser = Get-View $Datastore.ExtensionData.Browser

    # Determine all visible folders in the datastore
    $Folders = Get-ChildItem -Path $Datastore.DatastoreBrowserPath -Force | Where-Object {
        # Do not search hidden folders
        $_.PSIsContainer -and $_.Name -notmatch '^\.'
    } | Sort-Object Name

    foreach ($Folder in $Folders) {
        # Create DatastorePath for each folder
        $DatastorePath = "[" + $Datastore.Name + "] /" + $Folder.Name

        # Define search patterns
        $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
        # Search for all .vmdk files
        $SearchSpec.MatchPattern = @("*.vmdk")
        $SearchSpec.SearchCaseInsensitive = $true

        # Start search in specific folder using API
        $SearchResults = $DatastoreBrowser.SearchDatastoreSubFolders($DatastorePath, $SearchSpec)

        # Collect results
        foreach ($FolderResult in $SearchResults) {
            foreach ($File in $FolderResult.File) {
                # Check if file matches uncontrolled snapshot patterns (delta.vmdk or -flat.vmdk)
                # and doesn't match exception patterns
                if (($File.Path -match 'delta\.vmdk' -or $File.Path -match '-flat\.vmdk') -and
                    ($ExceptionFP -eq "" -or $File.Path -notmatch $ExceptionFP)) {
                    $items += [PSCustomObject]@{
                        Fullname   = $Datastore.DatastoreBrowserPath + '\' + $Folder.Name + '\' + $File.Path
                        FolderPath = $FolderResult.FolderPath.TrimEnd('/')
                        Datacenter = $Datastore.Datacenter
                    }
                }
            }
        }
    }

    $i++
}

# Process collected results
foreach ($vmFile in ($items | Sort-Object FolderPath)) {
    $vmFile.FolderPath -match '^\[([^\]]+)\] ([^/]+)' > $null
    $VMName = $matches[2]
    $eachVM = $FullVM | Where-Object { $_.Name -eq $VMName }
    if (!$eachVM.snapshot) {
        # Only process VMs without snapshots
        $vmdks += New-Object -TypeName PSObject -Property @{
            VM         = $eachVM.Name
            Datacenter = $vmFile.Datacenter
            Path       = $vmFile.Fullname
        }
    }
}

Write-Progress -ID 1 -Activity $pLang.pluginActivity -Status $pLang.Complete -Completed

# Output results
$vmdks

# Changelog
## 1.6 : Added setting to exclude DS
## 1.7 : Optimized using vSphere API SearchDatastoreSubFolders for significant performance improvement (reduces execution time from hours to minutes)
## 1.8 : Updated KB link to Broadcom Knowledge Base format and formatted as clickable HTML anchor tag
