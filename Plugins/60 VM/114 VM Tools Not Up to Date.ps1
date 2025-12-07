$Title = "VM Tools Not Up to Date"
$Header = "VM Tools Not Up to Date: [count]"
$Display = "Table"
$Author = "Alan Renouf, Shawn Masterson and Jonathan Pitre"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings
# Do not report on any VMs who are defined here (regex)
$VMTDoNotInclude = ""
# Maximum number of VMs shown (0 = no limit)
$VMTMaxReturn = 0
# Optionally fetch latest VMware Tools version from Broadcom KB (adds minor runtime)
$FetchLatestToolsVersion = $true
# End of Settings

# Update settings where there is an override
$VMTDoNotInclude = Get-vCheckSetting $Title "VMTDoNotInclude" $VMTDoNotInclude
$VMTMaxReturn = Get-vCheckSetting $Title "VMTMaxReturn" $VMTMaxReturn
$FetchLatestToolsVersion = Get-vCheckSetting $Title "FetchLatestToolsVersion" $FetchLatestToolsVersion

# Optionally scrape Broadcom KB 304809 for the latest VMware Tools version
$LatestToolsVersion = $null
if ($FetchLatestToolsVersion) {
   try {
      $resp = Invoke-WebRequest -Uri 'https://knowledge.broadcom.com/external/article/304809/build-numbers-and-versions-of-vmware-too.html' -UseBasicParsing -ErrorAction Stop
      $match = [regex]::Match($resp.Content, 'VMware Tools\s+(\d+\.\d+\.\d+)')
      if ($match.Success) {
         $LatestToolsVersion = $match.Groups[1].Value
      }
   } catch {
      # Ignore scraping errors; keep running
   }
}

# Treat these Tools version statuses as out-of-date/problematic (vSphere 7/8)
$OutdatedStatuses = @(
   "guestToolsNeedUpgrade",
   "guestToolsNotInstalled",
   "guestToolsUnmanaged",
   "guestToolsSupportedOld"
)

$query = $FullVM | Where-Object {
   $_.Name -notmatch $VMTDoNotInclude -and
   $_.Runtime.Powerstate -eq "poweredOn" -and
   $OutdatedStatuses -contains $_.ExtensionData.Guest.ToolsVersionStatus2
}

if ($VMTMaxReturn -gt 0) {
   $query = $query | Select-Object -First $VMTMaxReturn
}

$query |
Select-Object Name,
@{N = "Version"; E = { $_.Guest.ToolsVersion } },
@{N = "Status"; E = { $_.ExtensionData.Guest.ToolsVersionStatus2 } },
@{N = "RunningStatus"; E = { $_.ExtensionData.Guest.ToolsRunningStatus } } |
Sort-Object Name

$latestText = if ($LatestToolsVersion) { " Latest published VMware Tools version (scraped): $LatestToolsVersion." } else { "" }
$Comments = ("The following VMs have out-of-date or missing VMware Tools (Max Shown: {0} Exceptions: {1}).{2}" -f $VMTMaxReturn, $VMTDoNotInclude, $latestText)

# Changelog
## 1.0 : Initial Version
## 1.1 : Added Get-vCheckSetting
## 1.2 : Use ToolsVersionStatus2/RunningStatus (vSphere 8), expand statuses, add optional limit=0 for no cap
## 1.3 : Optional scrape of Broadcom KB 304809 to show latest published Tools version