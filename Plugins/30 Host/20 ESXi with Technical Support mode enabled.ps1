$Title = "ESXi with Technical Support mode or ESXi Shell enabled"
$Header = "ESXi Hosts with Tech Support Mode or ESXi Shell Enabled : [count]"
$Comments = "The following ESXi Hosts have Technical support mode or ESXi Shell enabled, this may not be the best security option. For more information see <a href='https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-security/index.html' target='_blank'>vSphere Security Configuration Guide</a> and <a href='https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-performance/index.html' target='_blank'>Performance Best Practices for VMware vSphere 8.0</a>."
$Display = "Table"
$Author = "Alan Renouf"
$PluginVersion = 1.5
$PluginCategory = "vSphere"

# Start of Settings 
# End of Settings 

$VMH | Where-Object { ($_.Version -lt 4.1) -and 
       ($_.ConnectionState -in @("Connected", "Maintenance")) -and 
       ($_.ExtensionData.Summary.Config.Product.Name -match "i") } | 
Select-Object Name, @{N = "TechSupportModeEnabled"; E = { ($_ | Get-AdvancedSetting -Name VMkernel.Boot.techSupportMode).value } } | 
Where-Object { $_.TechSupportModeEnabled -eq $true }

$VMH | Where-Object { ($_.Version -ge "4.1.0") -and 
       ($_.ConnectionState -in @("Connected", "Maintenance")) } | 
Select-Object Name, @{N = "TechSupportModeEnabled"; E = { ($_ | Get-VMHostService | Where-Object { $_.key -eq "TSM" }).Running } } | 
Where-Object { $_.TechSupportModeEnabled -eq $true }
       
