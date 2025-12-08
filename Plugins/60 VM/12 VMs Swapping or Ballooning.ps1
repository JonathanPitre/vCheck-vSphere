$Title = "VMs Ballooning or Swapping"
$Header = "VMs Ballooning or Swapping: [count]"
$Comments = "Ballooning and swapping may indicate a lack of memory or a limit on a VM, this may be an indication of not enough memory in a host or a limit held on a VM. For details see <a href='https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-resource-management/index.html' target='_blank'>VMware vSphere Memory Management and Monitoring</a>."
$Display = "Table"
$Author = "Alan Renouf, Frederic Martin"
$PluginVersion = 1.3
$PluginCategory = "vSphere"

# Start of Settings 
# End of Settings 

$FullVM | Where-Object { $_.runtime.PowerState -eq "PoweredOn" -and ($_.Summary.QuickStats.SwappedMemory -gt 0 -or $_.Summary.QuickStats.BalloonedMemory -gt 0) } | Select-Object Name, @{N = "SwapMB"; E = { $_.Summary.QuickStats.SwappedMemory } }, @{N = "MemBalloonMB"; E = { $_.Summary.QuickStats.BalloonedMemory } }

# Changelog
## 1.1 : Using quick stats property in order to avoid using Get-Stat cmdlet for performance matter
## 1.2 : Updated where clause to filter first
## 1.3 : Updated broken documentation link to official VMware vSphere Memory Management and Monitoring documentation