$Title = "vSAN Configuration Limits"
$Header = "vSAN Configuration Limits: [count]"
$Display = "Table"
$Author = "William Lam"
$PluginVersion = 1.1
$PluginCategory = "vSphere"

# Start of Settings
# Warning thresholds (% of maximum) per metric
$VsanHostThresholdPct = 45
$VsanComponentThresholdPct = 50
$VsanDiskGroupThresholdPct = 80
$VsanMDPerDGThresholdPct = 50
$VsanTotalMDThresholdPct = 50
$VsanVMsPerHostThresholdPct = 50
$VsanVMsPerClusterThresholdPct = 50
# End of Settings

# Update settings where there is an override
$VsanHostThresholdPct = Get-vCheckSetting $Title "VsanHostThresholdPct" $VsanHostThresholdPct
$VsanComponentThresholdPct = Get-vCheckSetting $Title "VsanComponentThresholdPct" $VsanComponentThresholdPct
$VsanDiskGroupThresholdPct = Get-vCheckSetting $Title "VsanDiskGroupThresholdPct" $VsanDiskGroupThresholdPct
$VsanMDPerDGThresholdPct = Get-vCheckSetting $Title "VsanMDPerDGThresholdPct" $VsanMDPerDGThresholdPct
$VsanTotalMDThresholdPct = Get-vCheckSetting $Title "VsanTotalMDThresholdPct" $VsanTotalMDThresholdPct
$VsanVMsPerHostThresholdPct = Get-vCheckSetting $Title "VsanVMsPerHostThresholdPct" $VsanVMsPerHostThresholdPct
$VsanVMsPerClusterThresholdPct = Get-vCheckSetting $Title "VsanVMsPerClusterThresholdPct" $VsanVMsPerClusterThresholdPct

function Get-VsanClusterHostMaximum {
    param(
        [Parameter(Mandatory = $true)]
        $ClusterView
    )
    # Default to modern maximum (64 hosts); older vSAN 5.5 was 32.
    $defaultMax = 64
    $legacyMax = 32

    $vsanVersion = $null
    try { $vsanVersion = $ClusterView.ConfigurationEx.VsanConfigInfo.ClusterConfigInfo.VsanVersion } catch {}

    # Fallback: infer from first host product version if vSAN version is not exposed
    if (-not $vsanVersion -and $ClusterView.Host.Count -gt 0) {
        $firstHost = Get-View -Id $ClusterView.Host[0] -Property Config.Product
        $vsanVersion = $firstHost.Config.Product.Version
    }

    if ($vsanVersion) {
        $major = 0
        $parts = $vsanVersion -split '\.'
        if ($parts.Count -ge 1) { [void][int]::TryParse($parts[0], [ref]$major) }
        if ($major -lt 6) { return $legacyMax } else { return $defaultMax }
    }

    return $defaultMax
}

function Get-VsanComponentMaximum {
    param(
        [Parameter(Mandatory = $true)]
        $ClusterView
    )
    # Modern vSAN (6.x+) supports ~9000 components per host; legacy 5.5 used 3000.
    $defaultMax = 9000
    $legacyMax = 3000

    $vsanVersion = $null
    try { $vsanVersion = $ClusterView.ConfigurationEx.VsanConfigInfo.ClusterConfigInfo.VsanVersion } catch {}
    if (-not $vsanVersion -and $ClusterView.Host.Count -gt 0) {
        $firstHost = Get-View -Id $ClusterView.Host[0] -Property Config.Product
        $vsanVersion = $firstHost.Config.Product.Version
    }

    if ($vsanVersion) {
        $major = 0
        $parts = $vsanVersion -split '\.'
        if ($parts.Count -ge 1) { [void][int]::TryParse($parts[0], [ref]$major) }
        if ($major -lt 6) { return $legacyMax } else { return $defaultMax }
    }

    return $defaultMax
}

$results = @()

# Static maxima (aligned to current vSAN 8.x/9.x ConfigMax; adjust if newer limits change)
$MaxDiskGroupsPerHost = 5      # OSA; ESA does not use disk groups
$MaxMDPerDiskGroup = 7      # OSA
$MaxTotalMDPerHost = 35     # OSA (5 * 7)
$MaxVMsPerHost = 1024   # vSphere/vSAN host max (current generation)
$MaxVMsPerCluster = 8000   # vSphere/vSAN cluster VM max (current generation)

foreach ($cluster in $clusviews) {
    if ($cluster.ConfigurationEx.VsanConfigInfo.Enabled) {
        # Cluster-level host maximum
        $vsanHostMax = Get-VsanClusterHostMaximum -ClusterView $cluster
        $totalHosts = ($cluster.Host | Measure-Object).Count
        $hostPct = if ($vsanHostMax) { [int](($totalHosts / $vsanHostMax) * 100) } else { 0 }
        if ($hostPct -gt $VsanHostThresholdPct) {
            $results += [PSCustomObject]@{
                Scope       = "Cluster"
                Name        = $cluster.Name
                Metric      = "HostsPerCluster"
                Value       = $totalHosts
                Maximum     = $vsanHostMax
                PercentUsed = $hostPct
            }
        }

        # Host-level component maximum
        $vsanComponentMax = Get-VsanComponentMaximum -ClusterView $cluster
        foreach ($vmhost in ($cluster.Host | Sort-Object -Property Name)) {
            $vmhostView = Get-View $vmhost -Property Name, ConfigManager.VsanSystem, ConfigManager.VsanInternalSystem
            $vsanSys = Get-View -Id $vmhostView.ConfigManager.VsanSystem
            $vsanIntSys = Get-View -Id $vmhostView.ConfigManager.VsanInternalSystem

            $vsanProps = @("lsom_objects_count", "owner")
            $resultsRaw = $vsanIntSys.QueryPhysicalVsanDisks($vsanProps)
            $vsanStatus = $vsanSys.QueryHostStatus()

            $componentCount = 0
            $json = $resultsRaw | ConvertFrom-Json
            foreach ($line in $json | Get-Member) {
                if ($vsanStatus.NodeUuid -eq $json.$($line.Name).owner) {
                    $componentCount += $json.$($line.Name).lsom_objects_count
                }
            }
            $compPct = if ($vsanComponentMax) { [int](($componentCount / $vsanComponentMax) * 100) } else { 0 }
            if ($compPct -gt $VsanComponentThresholdPct) {
                $results += [PSCustomObject]@{
                    Scope       = "Host"
                    Name        = $vmhostView.Name
                    Metric      = "ComponentsPerHost"
                    Value       = $componentCount
                    Maximum     = $vsanComponentMax
                    PercentUsed = $compPct
                }
            }

            # Disk groups per host (OSA)
            $diskGroups = ($vsanSys.Config.StorageInfo.DiskMapping | Measure-Object).Count
            $dgPct = if ($MaxDiskGroupsPerHost) { [int](($diskGroups / $MaxDiskGroupsPerHost) * 100) } else { 0 }
            if ($dgPct -gt $VsanDiskGroupThresholdPct) {
                $results += [PSCustomObject]@{
                    Scope       = "Host"
                    Name        = $vmhostView.Name
                    Metric      = "DiskGroupsPerHost"
                    Value       = $diskGroups
                    Maximum     = $MaxDiskGroupsPerHost
                    PercentUsed = $dgPct
                }
            }

            # MD per disk group (OSA)
            foreach ($diskMapping in $vsanSys.Config.StorageInfo.DiskMapping) {
                $mds = ($diskMapping.NonSsd | Measure-Object).Count
                $mdPct = if ($MaxMDPerDiskGroup) { [int](($mds / $MaxMDPerDiskGroup) * 100) } else { 0 }
                if ($mdPct -gt $VsanMDPerDGThresholdPct) {
                    $results += [PSCustomObject]@{
                        Scope       = "Host"
                        Name        = $vmhostView.Name
                        Metric      = "MagDisksPerDiskGroup"
                        Value       = $mds
                        Maximum     = $MaxMDPerDiskGroup
                        PercentUsed = $mdPct
                    }
                }
            }

            # Total MD per host (OSA)
            $totalMDs = 0
            foreach ($diskMapping in $vsanSys.Config.StorageInfo.DiskMapping) {
                $totalMDs += ($diskMapping.NonSsd | Measure-Object).Count
            }
            $totalMdPct = if ($MaxTotalMDPerHost) { [int](($totalMDs / $MaxTotalMDPerHost) * 100) } else { 0 }
            if ($totalMdPct -gt $VsanTotalMDThresholdPct) {
                $results += [PSCustomObject]@{
                    Scope       = "Host"
                    Name        = $vmhostView.Name
                    Metric      = "TotalMagDisksPerHost"
                    Value       = $totalMDs
                    Maximum     = $MaxTotalMDPerHost
                    PercentUsed = $totalMdPct
                }
            }

            # VMs per host
            $vmhostViewLight = Get-View $vmhost -Property Name, Vm
            $vmCountHost = ($vmhostViewLight.Vm | Measure-Object).Count
            $vmHostPct = if ($MaxVMsPerHost) { [int](($vmCountHost / $MaxVMsPerHost) * 100) } else { 0 }
            if ($vmHostPct -gt $VsanVMsPerHostThresholdPct) {
                $results += [PSCustomObject]@{
                    Scope       = "Host"
                    Name        = $vmhostView.Name
                    Metric      = "VMsPerHost"
                    Value       = $vmCountHost
                    Maximum     = $MaxVMsPerHost
                    PercentUsed = $vmHostPct
                }
            }
        }

        # VMs per cluster
        $clusterVMs = (Get-View -ViewType VirtualMachine -SearchRoot $cluster.MoRef -Property Name).Count
        $vmClusterPct = if ($MaxVMsPerCluster) { [int](($clusterVMs / $MaxVMsPerCluster) * 100) } else { 0 }
        if ($vmClusterPct -gt $VsanVMsPerClusterThresholdPct) {
            $results += [PSCustomObject]@{
                Scope       = "Cluster"
                Name        = $cluster.Name
                Metric      = "VMsPerCluster"
                Value       = $clusterVMs
                Maximum     = $MaxVMsPerCluster
                PercentUsed = $vmClusterPct
            }
        }
    }
}

$results

$Comments = ("vSAN limits check (hosts/cluster, components/host, DG/host, MD/DG, total MD/host, VMs/host, VMs/cluster). Reference: <a href='https://configmax.broadcom.com/guest?vmwareproduct=vSAN&release=9.0.0.0&categories=7-0' target='_blank'>ConfigMax</a>")

# Changelog
## 1.0 : Combined hosts-per-cluster and components-per-host checks, version-aware maxima, updated to ConfigMax link
## 1.1 : Added disk group, MD per DG, total MD per host, VMs per host/cluster; aligned maxima to current vSAN 8.x/9.x ConfigMax defaults (legacy falls back where detectable)

