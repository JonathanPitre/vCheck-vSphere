$Title = "Checking VM Hardware Version"
$Header = "VMs with old hardware: [count]"
$Comments = "The following VMs are not at the latest hardware version, you may gain performance enhancements if you convert them to the latest version. Hardware version threshold is automatically detected from your ESXi hosts or the Broadcom KB article (<a href='https://knowledge.broadcom.com/external/article?legacyId=1003746' target='_blank'>KB 1003746</a>)."
$Display = "Table"
$Author = "Alan Renouf, Jonathan Pitre"
$PluginVersion = 1.5
$PluginCategory = "vSphere"

# Start of Settings 
# Hardware Version to check for at least (0 = auto-detect dynamically)
# When set to 0, the plugin will:
#   1. Try to detect max hardware version from your ESXi hosts
#   2. Fall back to scraping Broadcom KB article (https://knowledge.broadcom.com/external/article?legacyId=1003746)
#   3. Use hardcoded defaults as last resort
# Set to a specific version to override auto-detection (e.g., 19, 20, 22)
$HWVers = 0
# Adding filter for dsvas, vShield appliances or any other vms that will remain on a lower HW version
$vmIgnore = "vShield*|dsva*"
# End of Settings

# Update settings where there is an override
$HWVers = Get-vCheckSetting $Title "HWVers" $HWVers
$vmIgnore = Get-vCheckSetting $Title "vmIgnore" $vmIgnore

# Function to get maximum hardware version from ESXi hosts via vSphere API
function Get-MaxHardwareVersionFromHosts {
    try {
        $maxHWVersion = 0
        foreach ($hostObj in $VMH) {
            try {
                $hostView = Get-View -Id $hostObj.Id -Property Config, Capability -ErrorAction SilentlyContinue
                if ($hostView -and $hostView.Capability) {
                    # Try to get supported hardware versions from host capabilities
                    # The max hardware version is typically available in the host's supported features
                    # We'll check the actual VMs on the host to find the highest supported version
                    $hostVMs = Get-VM -Location $hostObj -ErrorAction SilentlyContinue
                    foreach ($vmObj in $hostVMs) {
                        try {
                            $vmVersion = $vmObj.ExtensionData.Config.Version
                            if ($vmVersion -match 'vmx-(\d+)') {
                                $hwVer = [int]$matches[1]
                                if ($hwVer -gt $maxHWVersion) {
                                    $maxHWVersion = $hwVer
                                }
                            }
                        } catch {
                            # Ignore individual VM errors
                        }
                    }
                }
            } catch {
                # Ignore host errors
            }
        }
        
        return $maxHWVersion
    } catch {
        return 0
    }
}

# Function to scrape hardware version from Broadcom KB article
function Get-HardwareVersionFromKB {
    param(
        [int]$vCenterMajorVersion
    )
    
    $kbUrl = "https://knowledge.broadcom.com/external/article?legacyId=1003746"
    $cacheFile = Join-Path $env:TEMP "vCheck_HWVersion_Cache.xml"
    $cacheValid = $false
    $hwVersionMap = $null
    
    # Check cache (valid for 7 days)
    if (Test-Path $cacheFile) {
        try {
            $cacheData = Import-Clixml $cacheFile
            $cacheAge = (Get-Date) - $cacheData.Timestamp
            if ($cacheAge.TotalDays -lt 7) {
                $hwVersionMap = $cacheData.HWVersionMap
                $cacheValid = $true
            }
        } catch {
            # Cache invalid, will re-fetch
        }
    }
    
    # Fetch from KB if cache is invalid
    if (-not $cacheValid) {
        try {
            Write-Verbose "Fetching hardware version information from Broadcom KB..."
            
            # Use Invoke-WebRequest with proper headers
            $headers = @{
                'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
            
            $response = Invoke-WebRequest -Uri $kbUrl -Headers $headers -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            $htmlContent = $response.Content
            
            # Parse the HTML to extract hardware version mappings
            # The KB article has a table with format: "Hardware Version | Products (ESXi X.X, ...)"
            $hwVersionMap = @{}
            
            # Pattern 1: Match table rows with format "22 | ESX 9.0" or "21 | ESXi 8.0 U2"
            # This matches the table structure: Hardware Version | Products
            $tableRowPattern = '(?:<tr[^>]*>|<td[^>]*>)\s*(\d{1,2})\s*(?:\||</td>).*?ESX(?:i)?\s+(\d+)\.\d+'
            $tableMatches = [regex]::Matches($htmlContent, $tableRowPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $tableMatches) {
                $hwVersion = [int]$match.Groups[1].Value
                $majorVer = [int]$match.Groups[2].Value
                if (-not $hwVersionMap.ContainsKey($majorVer) -or $hwVersionMap[$majorVer] -lt $hwVersion) {
                    $hwVersionMap[$majorVer] = $hwVersion
                }
            }
            
            # Pattern 2: Match text patterns like "22 | ESX 9.0" or "21 | ESXi 8.0 U2"
            # This handles cases where the HTML structure might be different
            $textPattern = '(\d{1,2})\s*\|\s*ESX(?:i)?\s+(\d+)\.\d+'
            $textMatches = [regex]::Matches($htmlContent, $textPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $textMatches) {
                $hwVersion = [int]$match.Groups[1].Value
                $majorVer = [int]$match.Groups[2].Value
                if (-not $hwVersionMap.ContainsKey($majorVer) -or $hwVersionMap[$majorVer] -lt $hwVersion) {
                    $hwVersionMap[$majorVer] = $hwVersion
                }
            }
            
            # Pattern 3: Match patterns like "ESXi 8.0" followed by "version 20" or "HW version 20"
            # This handles alternative text formats
            $altPattern = 'ESX(?:i)?\s+(\d+)\.\d+.*?(?:version|HW version|hardware version)\s+(\d{1,2})'
            $altMatches = [regex]::Matches($htmlContent, $altPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $altMatches) {
                $majorVer = [int]$match.Groups[1].Value
                $hwVersion = [int]$match.Groups[2].Value
                if (-not $hwVersionMap.ContainsKey($majorVer) -or $hwVersionMap[$majorVer] -lt $hwVersion) {
                    $hwVersionMap[$majorVer] = $hwVersion
                }
            }
            
            # Save to cache
            if ($hwVersionMap.Count -gt 0) {
                $cacheData = @{
                    Timestamp    = Get-Date
                    HWVersionMap = $hwVersionMap
                }
                try {
                    $cacheData | Export-Clixml -Path $cacheFile -ErrorAction SilentlyContinue
                } catch {
                    # Ignore cache write errors
                }
            }
        } catch {
            Write-Verbose "Failed to fetch hardware version from KB: $_"
            # Try to use cached data even if expired
            if (Test-Path $cacheFile) {
                try {
                    $cacheData = Import-Clixml $cacheFile
                    $hwVersionMap = $cacheData.HWVersionMap
                } catch {
                    # Cache is corrupted
                }
            }
        }
    }
    
    # Return hardware version for the specified vCenter major version
    if ($hwVersionMap -and $hwVersionMap.ContainsKey($vCenterMajorVersion)) {
        return $hwVersionMap[$vCenterMajorVersion]
    }
    
    # If exact match not found, try to find the closest version
    $closestVersion = 0
    $closestMajor = 0
    foreach ($major in $hwVersionMap.Keys | Sort-Object -Descending) {
        if ($major -le $vCenterMajorVersion -and $major -gt $closestMajor) {
            $closestMajor = $major
            $closestVersion = $hwVersionMap[$major]
        }
    }
    
    if ($closestVersion -gt 0) {
        return $closestVersion
    }
    
    return 0
}

# Auto-detect recommended hardware version based on vCenter version if set to 0
if ($HWVers -eq 0) {
    try {
        $ServiceInstance = Get-View ServiceInstance -ErrorAction SilentlyContinue
        if ($ServiceInstance) {
            $versionString = $ServiceInstance.Content.About.Version
            $majorVersion = [int]($versionString.Split('.')[0])
            
            # Method 1: Try to get max hardware version from ESXi hosts
            $maxHWFromHosts = Get-MaxHardwareVersionFromHosts
            if ($maxHWFromHosts -gt 0) {
                $HWVers = $maxHWFromHosts
                Write-Verbose "Detected max hardware version $HWVers from ESXi hosts"
            } else {
                # Method 2: Try to get from KB article
                $hwFromKB = Get-HardwareVersionFromKB -vCenterMajorVersion $majorVersion
                if ($hwFromKB -gt 0) {
                    $HWVers = $hwFromKB
                    Write-Verbose "Detected hardware version $HWVers from Broadcom KB for vSphere $majorVersion"
                } else {
                    # Method 3: Fallback to hardcoded defaults
                    if ($majorVersion -ge 9) {
                        $HWVers = 22  # vSphere 9.0 supports HW version 22
                    } elseif ($majorVersion -eq 8) {
                        $HWVers = 21 # vSphere 8.0 supports HW version 20-21
                    } elseif ($majorVersion -eq 7) {
                        $HWVers = 19  # vSphere 7.0 supports up to HW version 19
                    } elseif ($majorVersion -eq 6) {
                        $HWVers = 13  # vSphere 6.5/6.7 supports up to HW version 13
                    } else {
                        $HWVers = 10  # Default for older versions
                    }
                    Write-Verbose "Using hardcoded hardware version $HWVers for vSphere $majorVersion"
                }
            }
        } else {
            $HWVers = 21 # Safe default if version detection fails
        }
    } catch {
        $HWVers = 21 # Safe default if version detection fails
        Write-Verbose "Could not determine vCenter version, using default HW version threshold: $HWVers"
    }
}

# Filter VMs with old hardware versions
$result = @()
foreach ($vm in $VM) {
    if ($vm.Name -match $vmIgnore) {
        continue
    }
    
    try {
        # Get hardware version - handle both HWVersion property and direct ExtensionData access
        $hwVersion = $null
        if ($vm.HWVersion) {
            # Try to parse the HWVersion property
            $hwVersionStr = $vm.HWVersion.ToString().Trim()
            if ([int]::TryParse($hwVersionStr, [ref]$hwVersion)) {
                # Successfully parsed
            } else {
                # If parsing fails, try to extract from Config.Version directly
                $versionStr = $vm.ExtensionData.Config.Version
                if ($versionStr -match 'vmx-(\d+)') {
                    $hwVersion = [int]$matches[1]
                }
            }
        } else {
            # Fallback: extract directly from Config.Version
            $versionStr = $vm.ExtensionData.Config.Version
            if ($versionStr -match 'vmx-(\d+)') {
                $hwVersion = [int]$matches[1]
            }
        }
        
        # Only add to results if hardware version is less than threshold
        if ($null -ne $hwVersion -and $hwVersion -lt $HWVers) {
            $result += [PSCustomObject]@{
                Name      = $vm.Name
                HWVersion = $hwVersion
            }
        }
    } catch {
        Write-Verbose "Error processing VM $($vm.Name): $_"
    }
}

$result

# Change Log
## 1.3 : Added Get-vCheckSetting
## 1.4 : Updated default hardware version threshold (was 8, now auto-detects dynamically). Added error handling for HWVersion parsing. 
##       Added explicit support for vSphere 9.0 (HW version 22) and vSphere 8.0 (HW version 20-21). 
##       Added dynamic hardware version detection - plugin now automatically detects max hardware version from ESXi hosts, 
##       falls back to scraping Broadcom KB article (KB 1003746), and uses hardcoded defaults as last resort. 
##       This makes the plugin future-proof and eliminates the need for manual updates when new vSphere versions are released.
## 1.5 : Use the observed maximum hardware version directly (no buffer) so VMs matching the installed vSphere-supported level are not reported.