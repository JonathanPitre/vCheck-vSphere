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
$PluginVersion = 1.10
$PluginCategory = "vSphere"

# Start of Settings
# Do not report uncontrolled snapshots on VMs that are defined here
$ExcludeDS = "ExcludeMe"
# Exception for specific file patterns (e.g., Xen-Desktop: "-xd-|-ctk.")
$ExceptionFP = ""
# Folder name regex to skip (e.g., "iso|templates|backups"), empty = none
$ExcludeFolderPattern = ""
# Show progress bars (disable to save a bit of time in very large environments)
$ShowProgress = $false
# End of Settings

# Variables for the results
$vmdks = @()
$items = @()

$i = 0
$datastoresToProcess = $Datastores | Where-Object { $_.Name -notmatch $ExcludeDS -and $_.State -eq "Available" }
foreach ($Datastore in $datastoresToProcess) {
    if ($ShowProgress) {
        Write-Progress -ID 2 -Parent 1 -Activity $pLang.pluginActivity -Status ($pLang.pluginStatus -f $i, $datastoresToProcess.count, $Datastore.Name) -PercentComplete ($i * 100 / $datastoresToProcess.count)
    }

    $DatastoreBrowser = Get-View $Datastore.ExtensionData.Browser

    # Determine all visible folders in the datastore (optional folder exclusion)
    $Folders = Get-ChildItem -Path $Datastore.DatastoreBrowserPath -Force | Where-Object {
        $_.PSIsContainer -and $_.Name -notmatch '^\.' -and
        ($ExcludeFolderPattern -eq "" -or $_.Name -notmatch $ExcludeFolderPattern)
    }

    foreach ($Folder in $Folders) {
        # Create DatastorePath for each folder
        $DatastorePath = "[" + $Datastore.Name + "] /" + $Folder.Name

        # Define search patterns — narrow to likely uncontrolled snapshot files
        $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
        $SearchSpec.MatchPattern = @("*.delta.vmdk", "*-flat.vmdk")
        $SearchSpec.SearchCaseInsensitive = $true

        # Start search in specific folder using API
        $SearchResults = $DatastoreBrowser.SearchDatastoreSubFolders($DatastorePath, $SearchSpec)

        # Collect results
        foreach ($FolderResult in $SearchResults) {
            foreach ($File in $FolderResult.File) {
                # Check if file matches uncontrolled snapshot patterns and doesn't match exception patterns
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
foreach ($vmFile in $items) {
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
# If progress is disabled, ensure we clear the top-level bar too (no-op if never shown)
if (-not $ShowProgress) {
    Write-Progress -ID 1 -Activity $pLang.pluginActivity -Status $pLang.Complete -Completed
}

# Output results
$vmdks

# Changelog
## 1.6 : Added setting to exclude DS
## 1.7 : Optimized using vSphere API SearchDatastoreSubFolders for significant performance improvement (reduces execution time from hours to minutes)
## 1.8 : Updated KB link to Broadcom Knowledge Base format and formatted as clickable HTML anchor tag
## 1.9 : Added setting to disable progress bars to shave runtime in large environments
## 1.10: Added folder exclusion setting, narrowed search patterns, and removed extra sorts for better performance
