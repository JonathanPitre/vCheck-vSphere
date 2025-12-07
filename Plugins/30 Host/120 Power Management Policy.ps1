$Title = "Host Power Management Policy"
$Comments = "The following hosts are not using the specified power management policy.  Power management may impact performance for latency sensitive workloads.  For details see <a href='https://www.vmware.com/docs/vsphere-esxi-vcenter-server-80-performance-best-practices'>Performance Best Practices for VMware vSphere 8.0</a>"
$Display = "Table"
$Author = "Doug Taliaferro & Jonathan Pitre"
$PluginVersion = 1.1
$PluginCategory = "vSphere"

# Start of Settings
# Which power management policy should your hosts use? For High Performance enter "static" (recommended for 2025 - ensures maximum performance for latency-sensitive workloads), for Balanced enter "dynamic" (this is the ESXi default policy), for Low power enter "low".
$PowerPolicy = "static"
# End of Settings

# Update settings where there is an override
$PowerPolicy = Get-vCheckSetting $Title "PowerPolicy" $PowerPolicy

$hostResults = @()
Foreach ($esxhost in ($HostsViews | Where-Object { $_.Runtime.ConnectionState -match "Connected|Maintenance" })) {
    If ($esxhost.config.PowerSystemInfo.CurrentPolicy.ShortName -ne $PowerPolicy) {
        $myObj = "" | Select-Object VMHost, PowerPolicy
        $myObj.VMHost = $esxhost.Name
        $myObj.PowerPolicy = $esxhost.config.PowerSystemInfo.CurrentPolicy.ShortName
        $hostResults += $myObj
    }
}

$hostResults

$Header = "Hosts not using Power Mangement Policy '$($PowerPolicy)' : [count]"