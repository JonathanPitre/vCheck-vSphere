$Title = "Missing ESX(i) updates and patches"
$Header = "Missing ESX(i) updates and patches: [count]"
$Comments = "The following updates and/or patches are not applied."
$Display = "Table"
$Author = "Luc Dekens, Jonathan Pitre"
$PluginVersion = 2.1
$PluginCategory = "vSphere"

# Start of Settings
# Optional: attempt vLCM remediation (vSphere 8+ only). Default = report-only.
$EnablevLCMRemediation = $false
# Mode: "Precheck" runs a vLCM precheck task, "Remediate" triggers remediation.
$vLCMRemediationMode = "Precheck"
# End of Settings

# Get vCenter version to determine which method to use
$vCenterVersion = $null
try {
    $ServiceInstance = Get-View ServiceInstance -ErrorAction SilentlyContinue
    if ($ServiceInstance) {
        $versionString = $ServiceInstance.Content.About.Version
        $majorVersion = [int]($versionString.Split('.')[0])
        $vCenterVersion = $majorVersion
    }
} catch {
    Write-Warning "Could not determine vCenter version: $_"
}

$result = @()

# vSphere 8.0+ uses vSphere Lifecycle Manager (vLCM) - VUM is deprecated
if ($vCenterVersion -ge 8) {
    try {
        # Try using ImageManager service (vLCM API)
        $imageManagerRef = $ServiceInstance.Content.ImageManager
        if ($null -eq $imageManagerRef) {
            Write-Warning "vSphere Lifecycle Manager (vLCM) ImageManager service is not available. Ensure vLCM is properly configured in vCenter."
        }
        $imageManager = if ($imageManagerRef) { Get-View -Id $imageManagerRef -ErrorAction SilentlyContinue } else { $null }
        
        if ($imageManager) {
            foreach ($esx in $VMH) {
                try {
                    $hostView = Get-View -Id $esx.Id -Property Name, Runtime, Config
                    $clusterObj = $esx | Get-Cluster -ErrorAction SilentlyContinue
                    $clusterName = if ($clusterObj) { $clusterObj.Name } else { "Standalone" }
                    
                    # Check compliance using ImageManager (works for both clustered and standalone hosts)
                    try {
                        $complianceInfo = $imageManager.CheckHostCompliance($hostView.MoRef)
                        
                        if ($complianceInfo -and $complianceInfo.ComplianceStatus -eq "NonCompliant") {
                            # Get missing components/updates
                            if ($complianceInfo.MissingComponents) {
                                foreach ($component in $complianceInfo.MissingComponents) {
                                    $kbUrl = ""
                                    if ($component.Description) {
                                        $kbMatch = [regex]::Match($component.Description, "(?<url>https?://[\w|\.|/]*\w{1})")
                                        if ($kbMatch.Success) {
                                            $kbUrl = $kbMatch.Groups['url'].Value
                                        }
                                    }
                                    
                                    $result += [PSCustomObject]@{
                                        Host        = $esx.Name
                                        Cluster     = $clusterName
                                        Baseline    = "vLCM Image"
                                        Name        = if ($component.Name) { $component.Name } else { $component.Version }
                                        ReleaseDate = if ($component.ReleaseDate) { $component.ReleaseDate.ToString() } else { "N/A" }
                                        IdByVendor  = if ($component.VendorId) { $component.VendorId } else { "N/A" }
                                        KB          = $kbUrl
                                    }
                                }
                            }
                            
                            # Also check for missing patches if available
                            if ($complianceInfo.MissingPatches) {
                                foreach ($patch in $complianceInfo.MissingPatches) {
                                    $kbUrl = ""
                                    if ($patch.Description) {
                                        $kbMatch = [regex]::Match($patch.Description, "(?<url>https?://[\w|\.|/]*\w{1})")
                                        if ($kbMatch.Success) {
                                            $kbUrl = $kbMatch.Groups['url'].Value
                                        }
                                    }
                                    
                                    $result += [PSCustomObject]@{
                                        Host        = $esx.Name
                                        Cluster     = $clusterName
                                        Baseline    = "vLCM Image"
                                        Name        = $patch.Name
                                        ReleaseDate = if ($patch.ReleaseDate) { $patch.ReleaseDate.ToString() } else { "N/A" }
                                        IdByVendor  = if ($patch.VendorId) { $patch.VendorId } else { "N/A" }
                                        KB          = $kbUrl
                                    }
                                }
                            }
                        }
                    } catch {
                        # If CheckHostCompliance doesn't work, try alternative approach
                        Write-Verbose "CheckHostCompliance method not available for host $($esx.Name), trying alternative method: $_"
                        
                        # Alternative: Check host's current image vs desired image (for clustered hosts)
                        try {
                            $cluster = $esx | Get-Cluster -ErrorAction SilentlyContinue
                            if ($cluster) {
                                $clusterView = Get-View -Id $cluster.Id -Property Name, ConfigurationEx
                                $hostConfig = $hostView.Config
                                
                                if ($hostConfig -and $clusterView.ConfigurationEx) {
                                    $desiredImage = $clusterView.ConfigurationEx.ImageSpec
                                    $currentImage = $hostConfig.ImageConfig
                                    
                                    if ($desiredImage -and $currentImage -and $desiredImage.Image -ne $currentImage.Image) {
                                        $result += [PSCustomObject]@{
                                            Host        = $esx.Name
                                            Cluster     = $clusterName
                                            Baseline    = "vLCM Image"
                                            Name        = "Image Update Required"
                                            ReleaseDate = "N/A"
                                            IdByVendor  = "N/A"
                                            KB          = ""
                                        }
                                    }
                                }
                            }
                        } catch {
                            Write-Verbose "Alternative compliance check failed for host $($esx.Name): $_"
                        }
                    }
                } catch {
                    Write-Verbose "Error processing host $($esx.Name): $_"
                }
            }
        } else {
            Write-Warning "vSphere Lifecycle Manager (vLCM) ImageManager service is not available. Ensure vLCM is properly configured in vCenter."
        }
    } catch {
        Write-Warning "vLCM compliance check failed. Ensure vSphere Lifecycle Manager is configured. Error: $_"
    }
}
# vSphere 6.x/7.x uses vSphere Update Manager (VUM)
elseif ($vCenterVersion -ge 6 -and $vCenterVersion -lt 8) {
    if (Get-Module -ListAvailable Vmware.VumAutomation -ErrorAction SilentlyContinue) {
        foreach ($esx in $VMH) {
            try {
                $compliance = Get-Compliance -Entity $esx -Detailed -ErrorAction SilentlyContinue
                $clusterObj = $esx | Get-Cluster -ErrorAction SilentlyContinue
                $clusterName = if ($clusterObj) { $clusterObj.Name } else { "Standalone" }
                foreach ($baseline in ($compliance | Where-Object { $_.Status -eq "NotCompliant" })) {
                    $baseline.NotCompliantPatches | ForEach-Object {
                        $kbUrl = ""
                        if ($_.Description) {
                            $kbMatch = [regex]::Match($_.Description, "(?<url>https?://[\w|\.|/]*\w{1})")
                            if ($kbMatch.Success) {
                                $kbUrl = $kbMatch.Groups['url'].Value
                            }
                        }
                        
                        $result += [PSCustomObject]@{
                            Host        = $esx.Name
                            Cluster     = $clusterName
                            Baseline    = $baseline.Baseline.Name
                            Name        = $_.Name
                            ReleaseDate = if ($_.ReleaseDate) { $_.ReleaseDate.ToString() } else { "N/A" }
                            IdByVendor  = $_.IdByVendor
                            KB          = $kbUrl
                        }
                    }
                }
            } catch {
                Write-Verbose "Error checking VUM compliance for host $($esx.Name): $_"
            }
        }
    } else {
        Write-Warning "vSphere Update Manager (VUM) PowerCLI module (Vmware.VumAutomation) is not installed. This plugin requires VUM for vSphere 6.x/7.x. For vSphere 8.0+, vLCM is used automatically."
    }
}
# Unknown or unsupported version
else {
    Write-Warning "Unable to determine vCenter version or unsupported version detected. This plugin supports vSphere 6.x, 7.x, and 8.0+."
}

$result

# Optional: vLCM remediation (vSphere 8+ only). Safe by default (precheck mode).
if ($vCenterVersion -ge 8 -and $EnablevLCMRemediation -and $result) {
    # Requires VMware.Lifecycle PowerCLI module (vLCM cmdlets)
    $lifecycleModule = Get-Module -ListAvailable VMware.Lifecycle -ErrorAction SilentlyContinue
    if (-not $lifecycleModule) {
        Write-Warning "vLCM remediation requested but VMware.Lifecycle module not installed. Install VMware.PowerCLI 13.2+ to enable vLCM cmdlets."
    } else {
        # Import the module so vLCM cmdlets are available
        Import-Module VMware.Lifecycle -ErrorAction Stop
        # Remediate per-cluster to avoid partial host remediation
        $nonCompliantClusters = $result | Select-Object -ExpandProperty Cluster -Unique | Where-Object { $_ -ne "Standalone" }
        foreach ($clusterName in $nonCompliantClusters) {
            try {
                $clusterObj = Get-Cluster -Name $clusterName -ErrorAction Stop
                if ($vLCMRemediationMode -eq "Remediate") {
                    Write-Host "Starting vLCM remediation for cluster '$clusterName'..." -ForegroundColor Cyan
                    Start-LcmClusterRemediation -Cluster $clusterObj -Confirm:$false
                } else {
                    Write-Host "Running vLCM precheck for cluster '$clusterName'..." -ForegroundColor Cyan
                    Start-LcmClusterPrecheck -Cluster $clusterObj -Confirm:$false
                }
            } catch {
                Write-Warning "vLCM remediation/precheck failed for cluster '$clusterName': $_"
            }
        }
        # Standalone hosts: attempt direct remediation if desired
        $standaloneHosts = $result | Where-Object { $_.Cluster -eq "Standalone" } | Select-Object -ExpandProperty Host -Unique
        foreach ($hostName in $standaloneHosts) {
            try {
                $hostObj = Get-VMHost -Name $hostName -ErrorAction Stop
                if ($vLCMRemediationMode -eq "Remediate") {
                    Write-Host "Starting vLCM remediation for host '$hostName'..." -ForegroundColor Cyan
                    Start-LcmHostRemediation -VMHost $hostObj -Confirm:$false
                } else {
                    Write-Host "Running vLCM precheck for host '$hostName'..." -ForegroundColor Cyan
                    Start-LcmHostPrecheck -VMHost $hostObj -Confirm:$false
                }
            } catch {
                Write-Warning "vLCM remediation/precheck failed for host '$hostName': $_"
            }
        }
    }
}

# Update comments based on version
if ($vCenterVersion -ge 8) {
    $Comments = "The following updates and/or patches are not applied (checked via vSphere Lifecycle Manager). For vSphere 8.0+, VUM has been replaced by vLCM. See <a href='https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-lifecycle-manager/index.html' target='_blank'>vSphere Lifecycle Manager Documentation</a> for more information."
} else {
    $Comments = "The following updates and/or patches are not applied (checked via vSphere Update Manager)."
}

# Changelog
## 1.2 : Replaced Get-PSSnapin with (Get-Module -ListAvailable Vmware.VumAutomation)
## 2.0 : Added support for vSphere 8.0+ using vSphere Lifecycle Manager (vLCM). Automatic version detection to use VUM (6.x/7.x) or vLCM (8.0+). Added error handling and fallback methods.

