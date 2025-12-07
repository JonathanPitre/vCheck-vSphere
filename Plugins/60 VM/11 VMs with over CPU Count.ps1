$Title = "VMs with over CPU Count"
$Display = "Table"
$Author = "Alan Renouf, Bill Wall"
$PluginVersion = 1.4
$PluginCategory = "vSphere"

# Start of Settings 
# Define the maximum amount of vCPUs your VMs are allowed
$vCPU = 4
# Include Powered off VMs?
$vCPUPoweredOff = $false
# Warn when a manual cores-per-socket layout is configured (may reduce performance)
$WarnOnCoresPerSocket = $true
# End of Settings

# Update settings where there is an override
$vCPU = Get-vCheckSetting $Title "vCPU" $vCPU
$WarnOnCoresPerSocket = Get-vCheckSetting $Title "WarnOnCoresPerSocket" $WarnOnCoresPerSocket

function Get-CoreLayoutInfo {
    param($vm)
    $coresPerSocket = $vm.ExtensionData.Config.Hardware.NumCoresPerSocket
    $sockets = if ($coresPerSocket -gt 0) { [math]::Ceiling($vm.NumCPU / $coresPerSocket) } else { $null }
    [PSCustomObject]@{
        CoresPerSocket = $coresPerSocket
        Sockets        = $sockets
    }
}

$vmScope = if ($vCPUPoweredOff) {
    $VM
} else {
    $VM | Where-Object { $_.PowerState -eq "PoweredOn" }
}

$vmScope |
ForEach-Object {
    $layout = Get-CoreLayoutInfo $_
    $issues = @()
    if ($_.NumCPU -gt $vCPU) {
        $issues += ("vCPU>{0}" -f $vCPU)
    }
    if ($WarnOnCoresPerSocket -and $_.NumCPU -gt 1 -and $layout.CoresPerSocket -gt 1) {
        $issues += ("Manual cores/socket={0}" -f $layout.CoresPerSocket)
    }
    if ($issues.Count -gt 0) {
        [PSCustomObject]@{
            Name           = $_.Name
            PowerState     = $_.PowerState
            NumCPU         = $_.NumCPU
            CoresPerSocket = $layout.CoresPerSocket
            Sockets        = $layout.Sockets
            Issue          = ($issues -join "; ")
        }
    }
} |
Sort-Object @{Expression = "NumCPU"; Descending = $true }, @{Expression = "Name"; Descending = $false }

$Header = ("VMs with over {0} vCPUs or manual cores-per-socket: [count]" -f $vCPU)
$Comments = ("The following VMs have over {0} CPU(s) or a manual cores-per-socket layout. High vCPU counts or static cores-per-socket settings can reduce performance and scheduling efficiency." -f $vCPU)

# Changelog
## 1.2 : Added Get-vCheckSetting
## 1.3 : Added Powered Off setting
## 1.4 : Warn on manual cores-per-socket layouts and include layout details
