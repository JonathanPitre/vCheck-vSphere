$Title = "Removable Media Connected"
$Header = "VMs with Removable Media Connected: [count]"
$Comments = "The following VMs have removable media connected (CD/DVD/Floppy). Mounted media can block vMotion (local ISO/host device), cause security/boot risks. vSphere 8.0 U2+ compatible."
$Display = "Table"
$Author = "Alan Renouf, Frederic Martin and Jonathan Pitre"
$PluginVersion = 1.2
$PluginCategory = "vSphere"

# Start of Settings 
# VMs with removable media not to report on
$IgnoreVMMedia = ""
# End of Settings

# Update settings where there is an override
$IgnoreVMMedia = Get-vCheckSetting $Title "IgnoreVMMedia" $IgnoreVMMedia

# Gather powered-on VMs and inspect removable media backings (CD/DVD/Floppy)
$FullVM |
Where-Object { $_.Runtime.PowerState -eq "PoweredOn" -and $_.Name -notmatch $IgnoreVMMedia } |
ForEach-Object {
   $vm = $_
   $vmName = $vm.Name
   $devices = $vm.Config.Hardware.Device

   # Floppy devices (report if connected)
   $devices | Where-Object { $_ -is [VMware.Vim.VirtualFloppy] -and $_.Connectable.Connected } |
   Select-Object @{Name = "VMName"; Expression = { $vmName } },
   @{Name = "Media Type"; Expression = { "Floppy" } },
   @{Name = "Media Path"; Expression = { $_.DeviceInfo.Summary } },
   @{Name = "Connection State"; Expression = { if ($_.Connectable.StartConnected) { "Connect at Power On" } elseif ($_.Connectable.Connected) { "Connected" } else { "Disconnected" } } },
   @{Name = "vMotion Risk"; Expression = { "Low" } }

   # CD/DVD devices
   $devices | Where-Object { $_ -is [VMware.Vim.VirtualCdrom] } | ForEach-Object {
      $cd = $_
      $backing = $cd.Backing
      $mediaPath = $null
      $datastoreName = $null
      $mediaType = "None"
      $connectionState = "Disconnected"

      if ($cd.Connectable) {
         if ($cd.Connectable.Connected) {
            $connectionState = "Connected"
         } elseif ($cd.Connectable.StartConnected) {
            $connectionState = "Connect at Power On"
         }
      }

      if ($backing -is [VMware.Vim.VirtualCdromIsoBackingInfo]) {
         $mediaPath = $backing.FileName
         $mediaType = "ISO Image"
         if ($mediaPath -match '^\[([^\]]+)\]') { $datastoreName = $Matches[1] }
      } elseif ($backing -is [VMware.Vim.VirtualCdromRemotePassthroughBackingInfo]) {
         $mediaType = "Host Device Passthrough"
         $mediaPath = $backing.DeviceName
         if ([string]::IsNullOrEmpty($mediaPath)) { $mediaPath = "Physical CD/DVD Drive" }
      } elseif ($backing -is [VMware.Vim.VirtualCdromRemoteAtapiBackingInfo]) {
         $mediaType = "Client Device"
         $mediaPath = "Client CD/DVD Drive"
      }

      # vMotion risk assessment
      $vMotionRisk = "Low"
      if ($mediaType -eq "Host Device Passthrough") {
         $vMotionRisk = "HIGH - Host Device"
      } elseif ($mediaType -eq "Client Device" -and $connectionState -eq "Connected") {
         $vMotionRisk = "MEDIUM - Client Device"
      } elseif ($mediaType -eq "ISO Image" -and $datastoreName) {
         try {
            $ds = Get-Datastore -Name $datastoreName -ErrorAction SilentlyContinue
            if ($ds -and $ds.ExtensionData.Summary.MultipleHostAccess -eq $false) {
               $vMotionRisk = "HIGH - Local Datastore"
            }
         } catch {
            # ignore lookup failures, keep default risk
         }
      }

      if ($mediaType -ne "None") {
         [PSCustomObject]@{
            VMName             = $vmName
            "Media Type"       = $mediaType
            "Media Path"       = $mediaPath
            "Connection State" = $connectionState
            "vMotion Risk"     = $vMotionRisk
         }
      }
   }
}

# Change Log
## 1.0 : Initial release
## 1.1 : Added Get-vCheckSetting
## 1.2 : Enhanced CD/DVD detection (ISO, host device, client device), vMotion risk assessment, vSphere 8.0 U2+ compatibility