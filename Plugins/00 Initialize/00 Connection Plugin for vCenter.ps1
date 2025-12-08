$Title = "Connection settings for vCenter"
$Author = "Alan Renouf"
$PluginVersion = 1.21
$Header = "Connection Settings"
$Comments = "Connection Plugin for connecting to vSphere"
$Display = "None"
$PluginCategory = "vSphere"

# Start of Settings
# Include SRM placeholder VMs in report?
$IncludeSRMPlaceholders = $false
# End of Settings

# Update settings where there is an override
# Check if Server was already set globally (from vCenterCreds.xml during config)
if ($global:Server) {
    $Server = $global:Server
} else {
    # Also check vCenterCreds.xml file directly
    $vCenterCredFile = Join-Path $ScriptPath "vCenterCreds.xml"
    if (Test-Path $vCenterCredFile) {
        try {
            $creds = Import-Clixml $vCenterCredFile
            if ($creds.Server) {
                $Server = $creds.Server
            }
        } catch {
            # If file read fails, continue with Get-vCheckSetting
        }
    }
    # Only prompt if not already set
    if ($Server -eq "192.168.0.0") {
        $Server = Get-vCheckSetting $Title "Server" $Server
    }
}

# Setup plugin-specific language table
$pLang = DATA {
    ConvertFrom-StringData @'
      connReuse = Re-using connection to VI Server
      connOpen  = Connecting to VI Server
      connError = Unable to connect to vCenter, please ensure you have altered the vCenter server address correctly. To specify a username and password edit the connection string in the file $GlobalVariables
      custAttr  = Adding Custom properties
      collectVM = Collecting VM Objects
      collectHost = Collecting VM Host Objects
      collectCluster = Collecting Cluster Objects
      collectDatastore = Collecting Datastore Objects
      collectDVM = Collecting Detailed VM Objects
      collectTemplate = Collecting Template Objects
      collectDVIO = Collecting Detailed VI Objects
      collectAlarm = Collecting Detailed Alarm Objects
      collectDHost = Collecting Detailed VMHost Objects
      collectDCluster = Collecting Detailed Cluster Objects
      collectDDatastore = Collecting Detailed Datastore Objects
      collectDDatastoreCluster = Collecting Detailed Datastore Cluster Objects
      collectAlarms = Collecting Alarm Definitions
'@
}
# Override the default (en) if it exists in lang directory
Import-LocalizedData -BaseDirectory (Join-Path $ScriptPath "Lang") -BindingVariable pLang -ErrorAction SilentlyContinue

# Find the VI Server and port from the global settings file
$serverParts = $Server -Split ":"
$VIServer = $serverParts[0]
$port = if ($serverParts[1]) { $serverParts[1] } else { 443 }

# Bail out early if no usable server was provided
if ([string]::IsNullOrWhiteSpace($VIServer) -or $VIServer -eq "192.168.0.0") {
    throw "vCheck aborted: vCenter server is not set. Please update the Server setting or vCenterCreds.xml."
}

# Path to vCenter credentials file which will be created if not already existing
$vCenterCredFile = Join-Path $ScriptPath "vCenterCreds.xml"

function Get-CorePlatform {
    <#
    .SYNOPSIS
        Gets the core platform of the system.

    .DESCRIPTION
        This function returns the core platform of the system, including OS family, version, hostname, and architecture.

    .EXAMPLE
        Get-CorePlatform
        Returns platform information for the current system.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
        Returns an ordered dictionary containing OSDetected, OSFamily, OS, Version, Hostname, and Architecture.

    .NOTES
        Thanks to @Lucd22 (Lucd.info) for this great function!
    #>
    [CmdletBinding()]
    param()
    $osDetected = $false
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-Verbose -Message 'Windows detected'
        $osDetected = $true
        $osFamily = 'Windows'
        $osName = $os.Caption
        $osVersion = $os.Version
        $nodeName = $os.CSName
        $architecture = $os.OSArchitecture
    } catch {
        Write-Verbose -Message 'Possibly Linux or Mac'
        $uname = "$(uname)"
        if ($uname -match '^Darwin|^Linux') {
            $osDetected = $true
            $osFamily = $uname
            $osName = "$(uname -v)"
            $osVersion = "$(uname -r)"
            $nodeName = "$(uname -n)"
            $architecture = "$(uname -p)"
        }
        # Other
        else {
            Write-Warning -Message "Kernel $($uname) not covered"
        }
    }
    [ordered]@{
        OSDetected   = $osDetected
        OSFamily     = $osFamily
        OS           = $osName
        Version      = $osVersion
        Hostname     = $nodeName
        Architecture = $architecture
    }
}

$Platform = Get-CorePlatform
switch ($Platform.OSFamily) {
    { $_ -in "Darwin", "Linux" } {
        $tempLocation = "/tmp"
        $OutputPath = $tempLocation
        Get-Module -ListAvailable PowerCLI* | Import-Module
    }
    "Windows" {
        $tempLocation = "$ENV:Temp"
        $pcliCore = 'VMware.VimAutomation.Core'
        $pssnapinPresent = $false
        $psmodulePresent = $false

        if (Get-Module -Name $pcliCore -ListAvailable) {
            $psmodulePresent = $true
            if (!(Get-Module -Name $pcliCore)) {
                Import-Module -Name $pcliCore
            }
        }

        if (Get-PSSnapin -Name $pcliCore -Registered -ErrorAction SilentlyContinue) {
            $pssnapinPresent = $true
            if (!(Get-PSSnapin -Name $pcliCore -ErrorAction SilentlyContinue)) {
                Add-PSSnapin -Name $pcliCore
            }
        }

        if (!$pssnapinPresent -and !$psmodulePresent) {
            Write-Error "Can't find PowerCLI. Is it installed?"
            return
        }
    }
}

$OpenConnection = $global:DefaultVIServers | Where-Object { $_.Name -eq $VIServer }
if ($OpenConnection.IsConnected) {
    Write-CustomOut ("{0}: {1}" -f $pLang.connReuse, $Server)
    $VIConnection = $OpenConnection
} else {
    # Check if credentials file exists and has valid credentials
    $hasValidCredentials = $false
    if (Test-Path $vCenterCredFile) {
        try {
            $LoadedCredentials = Get-vCenterCredentials($vCenterCredFile)
            # Validate that credentials are complete (Username and Password both exist)
            if ($LoadedCredentials -and 
                $LoadedCredentials.Username -and 
                $LoadedCredentials.Password -and 
                $null -ne $LoadedCredentials.Password) {
                $hasValidCredentials = $true
            }
        } catch {
            # Credentials file exists but is invalid, will prompt for new credentials
            $hasValidCredentials = $false
        }
    }
    
    # If no valid credentials, prompt for them
    if (-not $hasValidCredentials) {
        $LoadedCredentials = Set-vCenterCredentials($vCenterCredFile, $Server)
    }
    
    if (-not $LoadedCredentials -or -not $LoadedCredentials.Username -or -not $LoadedCredentials.Password) {
        throw "vCheck aborted: vCenter credentials are missing or incomplete."
    }
    $vCenterCreds = New-Object System.Management.Automation.PsCredential($LoadedCredentials.Username, $LoadedCredentials.Password)
    Write-CustomOut ("{0}: {1}" -f $pLang.connOpen, $Server)

    $connectionError = $null
    $promptedForNewCreds = $false
    do {
        try {
            $VIConnection = Connect-VIServer -Server $VIServer -Port $Port -Credential $vCenterCreds -ErrorAction Stop
            $connectionError = $null
        } catch {
            $connectionError = $_
            if (-not $promptedForNewCreds) {
                Write-Warning "Stored vCenter credentials failed. Prompting for new credentials..."
                $LoadedCredentials = Set-vCenterCredentials($vCenterCredFile, $Server)
                $vCenterCreds = New-Object System.Management.Automation.PsCredential($LoadedCredentials.Username, $LoadedCredentials.Password)
                $promptedForNewCreds = $true
            } else {
                break
            }
        }
    } while ($connectionError)
}

if (-not $VIConnection -or -not $VIConnection.IsConnected) {
    Write-Error $pLang.connError
    if ($connectionError) { Write-Error $connectionError }
    throw "vCheck aborted: unable to connect to vCenter $VIServer on port $Port."
}

function Get-VMFolderPath {
    <#
    .SYNOPSIS
        Gets the VM folder path from Datacenter to the folder that contains the VM.
    
    .DESCRIPTION
        This function returns the VM folder path. As a parameter it takes the
        current folder in which the VM resides. This function can return
        either 'name' or 'moref' output. Moref output can be obtained
        using the -moref switch.
    
    .PARAMETER folderid
        This is the moref of the parent directory for VM. Our starting
        point. Can be obtained in several ways. One way is to get it
        by: (get-vm 'vm123'|get-view).parent
        or: (get-view -viewtype virtualmachine -Filter @{'name'='vm123'}).parent
    
    .PARAMETER moref
        Add -moref when invoking function to obtain moref values.
    
    .EXAMPLE
        Get-VM 'vm123' | Get-VMFolderPath
        Function will take folderid parameter from pipeline.
    
    .EXAMPLE
        Get-VMFolderPath (Get-VM myvm123|Get-View).parent
        Function has to take as first parameter the moref of VM parent folder.
        DC\VM\folder2\folderX\vmvm123
        Parameter will be the folderX moref.
    
    .EXAMPLE
        Get-VMFolderPath (Get-VM myvm123|Get-View).parent -moref
        Instead of names in output, morefs will be given.
    
    .OUTPUTS
        System.String
        Returns the folder path as a string, either with names or morefs depending on the -moref switch.
    
    .NOTES
        NAME: Get-VMFolderPath
        AUTHOR: Grzegorz Kulikowski
        LASTEDIT: 09/14/2012
        NOT WORKING ? #powercli @ irc.freenode.net
    
    .LINK
        http://psvmware.wordpress.com
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$folderid,
        [switch]$moref
    )

    $folderparent = get-view $folderid
    if ($folderparent.name -ne 'vm') {
        $path = if ($moref) { 
            $folderparent.moref.toString() + '\' + $path 
        } else { 
            $folderparent.name + '\' + $path 
        }
        if ($folderparent.parent) {
            if ($moref) { 
                get-vmfolderpath $folderparent.parent.tostring() -moref 
            } else { 
                get-vmfolderpath $folderparent.parent.tostring()
            }
        }
    } else {
        $parentView = get-view $folderparent.parent
        if ($moref) {
            return $parentView.moref.tostring() + '\' + $folderparent.moref.tostring() + '\' + $path
        } else {
            return $parentView.name.toString() + '\' + $folderparent.name.toString() + '\' + $path
        }
    }
}

Write-CustomOut $pLang.custAttr

function Get-VMLastPoweredOffDate {
    <#
    .SYNOPSIS
        Gets the last powered off date for a virtual machine.

    .DESCRIPTION
        This function retrieves the last date when a virtual machine was powered off.
        The event query is limited to the last 3 years to prevent memory issues with VMs
        that have extensive event history.

    .PARAMETER vm
        The virtual machine object for which to retrieve the last powered off date.

    .EXAMPLE
        Get-VM 'MyVM' | Get-VMLastPoweredOffDate
        Returns the last powered off date for the specified VM.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with Name and LastPoweredOffDate properties.

    .NOTES
        This function limits event queries to the last 3 years to improve performance
        and reduce memory usage (Issue #765).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]
        $vm
    )
    process {
        $startDate = (Get-Date).AddYears(-3)
        [PSCustomObject]@{
            Name               = $_.Name
            LastPoweredOffDate = (Get-VIEventPlus -Entity $vm -Start $startDate | 
                Where-Object { $_.Gettype().Name -eq "VmPoweredOffEvent" } | 
                Select-Object -First 1).CreatedTime
        }
    }
}

function Get-VMLastPoweredOnDate {
    <#
    .SYNOPSIS
        Gets the last powered on date for a virtual machine.

    .DESCRIPTION
        This function retrieves the last date when a virtual machine was powered on.
        The event query is limited to the last 3 years to prevent memory issues with VMs
        that have extensive event history.

    .PARAMETER vm
        The virtual machine object for which to retrieve the last powered on date.

    .EXAMPLE
        Get-VM 'MyVM' | Get-VMLastPoweredOnDate
        Returns the last powered on date for the specified VM.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with Name and LastPoweredOnDate properties.

    .NOTES
        This function limits event queries to the last 3 years to improve performance
        and reduce memory usage (Issue #765).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]
        $vm
    )

    process {
        $startDate = (Get-Date).AddYears(-3)
        [PSCustomObject]@{
            Name              = $_.Name
            LastPoweredOnDate = (Get-VIEventPlus -Entity $vm -Start $startDate | 
                Where-Object { $_.Gettype().Name -match "VmPoweredOnEvent" } | 
                Select-Object -First 1).CreatedTime
        }
    }
}

New-VIProperty -Name LastPoweredOffDate -ObjectType VirtualMachine -Value { (Get-VMLastPoweredOffDate -vm $Args[0]).LastPoweredOffDate } -Force -ErrorAction SilentlyContinue | Out-Null
New-VIProperty -Name LastPoweredOnDate  -ObjectType VirtualMachine -Value { (Get-VMLastPoweredOnDate  -vm $Args[0]).LastPoweredOnDate }  -Force -ErrorAction SilentlyContinue | Out-Null

New-VIProperty -Name PercentFree -ObjectType Datastore -Value {
    param($ds)
    [math]::Round((100 * $ds.FreeSpaceMB / $ds.CapacityMB), 2)
} -Force | Out-Null

New-VIProperty -Name "HWVersion" -ObjectType VirtualMachine -Value {
    param($vm)
    $vm.ExtensionData.Config.Version.Substring(4)
} -BasedOnExtensionProperty "Config.Version" -Force | Out-Null

Write-CustomOut $pLang.collectVM
$VM = Get-VM | 
Where-Object { $IncludeSRMPlaceholders -or $_.ExtensionData.Config.ManagedBy.Type -ne "placeholderVm" } | 
Sort-Object Name

if ($VMFolder) {
    $VM = $VM | Where-Object { "$(Get-VMFolderPath $_.folderid)" -like "*$VMFolder*" } | Sort-Object Name
}

Write-CustomOut $pLang.collectHost
$VMH = Get-VMHost | Sort-Object Name
Write-CustomOut $pLang.collectCluster
$Clusters = Get-Cluster | Sort-Object Name
Write-CustomOut $pLang.collectDatastore
$Datastores = Get-Datastore | Sort-Object Name
Write-CustomOut $pLang.collectDVM
$FullVM = Get-View -ViewType VirtualMachine | 
Where-Object { 
    -not $_.Config.Template -and 
    ($IncludeSRMPlaceholders -or $_.Config.ManagedBy.ExtensionKey -ne 'com.vmware.vcDr')
}

if ($VMFolder) {
    $FullVM = $FullVM | Where-Object { $_.Name -in $VM.Name }
}

Write-CustomOut $pLang.collectTemplate
$VMTmpl = Get-Template
Write-CustomOut $pLang.collectDVIO
$ServiceInstance = get-view ServiceInstance
Write-CustomOut $pLang.collectAlarm
$alarmMgr = get-view $ServiceInstance.Content.alarmManager
Write-CustomOut $pLang.collectDHost
$HostsViews = Get-View -ViewType HostSystem
Write-CustomOut $pLang.collectDCluster
$clusviews = Get-View -ViewType ClusterComputeResource
Write-CustomOut $pLang.collectDDatastore
$storageviews = Get-View -ViewType Datastore
Write-CustomOut $pLang.collectAlarms
$valarms = $alarmMgr.GetAlarm($null) | Select-Object value, @{N = "name"; E = { (Get-View -Id $_).Info.Name } }

# Find out which version of the API we are connecting to
$VIVersion = ((Get-View ServiceInstance).Content.About.Version).Chars(0)

# Check to see if its a VCSA or not
$VCSA = $ServiceInstance.Client.ServiceContent.About.OsType -eq "linux-x64"

# Check for vSphere
$vSphere = $VIVersion -ge 4

if ($VIVersion -ge 5) {
    Write-CustomOut $pLang.collectDDatastoreCluster
    $DatastoreClustersView = Get-View -ViewType StoragePod
}


function Get-VIEventPlus {
    <#
    .SYNOPSIS
        Returns vSphere events

    .DESCRIPTION
        The function will return vSphere events. With the available parameters, the execution time can be improved, compared to the original Get-VIEvent cmdlet.

    .PARAMETER Entity
        When specified the function returns events for the specific vSphere entity. By default events for all vSphere entities are returned.

    .PARAMETER EventType
        This parameter limits the returned events to those specified on this parameter.

    .PARAMETER EventCategory
        This parameter limits the returned events to the specified category. (info, warning, error)

    .PARAMETER Start
        The start date of the events to retrieve

    .PARAMETER Finish
        The end date of the events to retrieve.

    .PARAMETER Recurse
        A switch indicating if the events for the children of the Entity will also be returned

    .PARAMETER User
        The list of usernames for which events will be returned

    .PARAMETER System
        A switch that allows the selection of all system events.

    .PARAMETER ScheduledTask
        The name of a scheduled task for which the events will be returned

    .PARAMETER FullMessage
        A switch indicating if the full message shall be compiled. This switch can improve the execution speed if the full message is not needed.

    .PARAMETER UseUTC
        A switch indicating if the event should remain in UTC or local time.

    .EXAMPLE
        PS> Get-VIEventPlus -Entity $vm
        Returns events for the specified virtual machine.

    .EXAMPLE
        PS> Get-VIEventPlus -Entity $cluster -Recurse:$true
        Returns events for the cluster and all child entities.

    .OUTPUTS
        System.Collections.Generic.List[PSObject]
        Returns a list of vSphere event objects.

    .NOTES
        Author: Luc Dekens
    #>
    [CmdletBinding()]
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.InventoryItem[]]
        $Entity,
        [string[]]
        $EventType,
        [ValidateSet('info', 'warning', 'error')]
        [string[]]
        $EventCategory,
        [DateTime]
        $Start,
        [DateTime]
        $Finish = (Get-Date),
        [switch]
        $Recurse,
        [string[]]
        $User,
        [switch]
        $System,
        [string]
        $ScheduledTask,
        [switch]
        $FullMessage = $false,
        [switch]
        $UseUTC = $false
    )

    process {
        $eventnumber = 1000  # Increase the number of events retrieved per call
        $events = New-Object System.Collections.Generic.List[PSObject]
        $eventMgr = Get-View EventManager
        $eventFilter = New-Object VMware.Vim.EventFilterSpec
        $eventFilter.disableFullMessage = ! $FullMessage
        $eventFilter.entity = New-Object VMware.Vim.EventFilterSpecByEntity
        $eventFilter.entity.recursion = if ($Recurse) { "all" } else { "self" }
        $eventFilter.eventTypeId = $EventType
        $eventFilter.Category = $EventCategory
        if ($Start -or $Finish) {
            $eventFilter.time = New-Object VMware.Vim.EventFilterSpecByTime
            if ($Start) {
                $eventFilter.time.beginTime = $Start
            }
            if ($Finish) {
                $eventFilter.time.endTime = $Finish
            }
        }
        if ($User -or $System) {
            $eventFilter.UserName = New-Object VMware.Vim.EventFilterSpecByUsername
            if ($User) {
                $eventFilter.UserName.userList = $User
            }
            if ($System) {
                $eventFilter.UserName.systemUser = $System
            }
        }
        if ($ScheduledTask) {
            $si = Get-View ServiceInstance
            $schTskMgr = Get-View $si.Content.ScheduledTaskManager
            $eventFilter.ScheduledTask = Get-View $schTskMgr.ScheduledTask |
            Where-Object { $_.Info.Name -match $ScheduledTask } |
            Select-Object -First 1 |
            Select-Object -ExpandProperty MoRef
        }
        if (!$Entity) {
            $Entity = @(Get-Folder -NoRecursion)
        }
        $entity | Foreach-Object {
            $eventFilter.entity.entity = $_.ExtensionData.MoRef
            $eventCollector = Get-View ($eventMgr.CreateCollectorForEvents($eventFilter))
            $eventsBuffer = $eventCollector.ReadNextEvents($eventnumber)
            while ($eventsBuffer) {
                ForEach ($Item in $eventsBuffer) {
                    if (-not $UseUTC) {
                        $Item.CreatedTime = $Item.CreatedTime.ToLocalTime()
                    }
                    $events.add($Item)
                }
                $eventsBuffer = $eventCollector.ReadNextEvents($eventnumber)  # Continue reading events
            }
            $eventCollector.DestroyCollector()
        }

        $events
    }
}

function Get-FriendlyUnit {
    <#
    .SYNOPSIS
        Convert numbers into smaller binary multiples.

    .DESCRIPTION
        The function accepts a value and will convert it into the biggest binary unit available.
        This makes large numbers more readable by converting them to appropriate units (KB, MB, GB, etc.).

    .PARAMETER Value
        The value you want to convert. This number must be positive.

    .PARAMETER IEC
        A switch to indicate if the function shall return the IEC unit names (KiB, MiB, GiB, etc.),
        or the more commonly used unit names (KB, MB, GB, etc.).
        The default is to use the commonly used unit names.

    .EXAMPLE
        PS> Get-FriendlyUnit -Value 123456
        Converts 123456 bytes to a friendly format.

    .EXAMPLE
        PS> 123456 | Get-FriendlyUnit -IEC
        Converts 123456 bytes using IEC unit names.

    .EXAMPLE
        PS> Get-FriendlyUnit -Value 123456,789123, 45678
        Converts multiple values to friendly formats.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns an object with Value and Unit properties.

    .NOTES
        Author: Luc Dekens
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [double[]]$Value,
        [switch]$IEC
    )

    begin {
        $OldUnits = "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"
        $IecUnits = "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"
        if ($IEC) { $units = $IecUnits }else { $units = $OldUnits }
    }

    process {
        $Value | ForEach-Object {
            if ($_ -lt 0) {
                write-Error "Numbers must be positive."
                break
            }
            $modifier = if ($_ -gt 0) {
                [math]::Floor([Math]::Log($_, 1KB))
            } else {
                0
            }
            New-Object PSObject -Property @{
                Value = $_ / [math]::Pow(1KB, $modifier)
                Unit  = & { if ($modifier -lt $units.Count) { $units[$modifier] }else { "1KB E{0}" -f $modifier } }
            }
        }
    }
}

function Get-HttpDatastoreItem {
    <#
    .SYNOPSIS
        Get file and folder info from datastore.

    .DESCRIPTION
        This function will retrieve a file and folders list from a datastore.
        The function uses the HTTP access to a datastore to obtain the list.

    .PARAMETER Server
        The vSphere server connection. Defaults to the global default server.

    .PARAMETER Datastore
        The datastore for which to retrieve the list. This parameter is required when using the Datastore parameter set.

    .PARAMETER Path
        The folder path from where to start listing files and folders.
        The default is to start from the root of the datastore. This parameter is required when using the Path parameter set.

    .PARAMETER Credential
        A credential for an account that has access to the datastore.

    .PARAMETER Recurse
        A switch that defines if the files and folders list shall be recursive.

    .PARAMETER IncludeRoot
        A switch to indicate if the root of the search path shall be included.

    .PARAMETER Unit
        A switch that defines if the filesize shall be returned in friendly units.
        Requires the Get-FriendlyUnit function.

    .EXAMPLE
        PS> Get-HttpDatastoreItem -Datastore DS1 -Credential $cred
        Retrieves files and folders from datastore DS1.

    .EXAMPLE
        PS> Get-Datastore | Get-HttpDatastoreItem -Credential $cred
        Retrieves files and folders from all datastores via pipeline.

    .EXAMPLE
        PS> Get-Datastore | Get-HttpDatastoreItem -Credential $cred -Recurse
        Retrieves files and folders recursively from all datastores.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns objects with Name, FullName, Timestamp, Size, and optionally Unit properties.

    .NOTES
        Author: Luc Dekens
    #>
    [CmdletBinding()]
    param(
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$Server = $global:DefaultVIServer,
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName, ParameterSetName = 'Datastore')]
        [Alias('Name')]
        [string]$Datastore,
        [parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path = '',
        [PSCredential]$Credential,
        [Switch]$Recurse = $false,
        [Switch]$IncludeRoot = $false,
        [Switch]$Unit = $false
    )

    Begin {
        $regEx = [RegEx]'<tr><td><a.*?>(?<Filename>.*?)</a></td><td.*?>(?<Timestamp>.*?)</td><td.*?>(?<Filesize>[0-9]+|[ -]+)</td></tr>'
    }

    Process {
        Write-Verbose -Message "$(Get-Date) $($s = Get-PSCallStack;">Entering {0}" -f $s[0].FunctionName)"
        Write-Verbose -Message "$(Get-Date) Datastore:$($Datastore)  Path:$($Path)"
        Write-Verbose -Message "$(Get-Date) Recurse:$($Recurse.IsPresent)"

        Switch ($PSCmdlet.ParameterSetName) {
            'Datastore' {
                # No folder path specified when using Datastore parameter
            }
            'Path' {
                $Datastore, $folderQualifier = $Path.Split('\[\] /', [System.StringSplitOptions]::RemoveEmptyEntries)

                if (-not $folderQualifier) {
                    $lastParent = ''
                    $lastQualifier = ''
                } else {
                    if ($folderQualifier.Count -eq 1) {
                        $lastParent = ''
                        $lastQualifier = "$($folderQualifier)$(if($Path -match "/$"){'/'})"
                    } else {
                        $lastQualifier = "$($folderQualifier[-1])$(if($Path -match "/$"){'/'})"
                        $lastParent = "$($folderQualifier[0..($folderQualifier.Count-2)] -join '/')/"
                    }
                }
            }
            Default {
                Throw "Invalid parameter combination"
            }
        }
        $folderQualifier = $folderQualifier -join '/'
        if ($Path -match "/$" -and $folderQualifier -notmatch "/$") {
            $folderQualifier += '/'
        }
        $stack = Get-PSCallStack | Select-Object -ExpandProperty Command
        if (($stack | Group-Object -AsHashTable -AsString)[$stack[0]].Count -eq 1) {
            Write-Verbose "First call"
            $sDFile = @{
                Server      = $Server
                Credential  = $Credential
                Path        = "[$($Datastore)]$(if($lastParent){"" $($lastParent)""})"
                Recurse     = $Recurse.IsPresent
                IncludeRoot = $IncludeRoot.IsPresent
                Unit        = $Unit.IsPresent
            }
            $allEntry = Get-HttpDatastoreItem @sDFile
            $entry = $allEntry | Where-Object { $_.Name -match "^$($lastQualifier)/*$" }
            if ($entry.Name -match "\/$") {
                # It's a folder
                if ($lastQualifier -notmatch "/$") {
                    $folderQualifier += '/'
                }
                if ($IncludeRoot.IsPresent) {
                    $entry
                }
            } else {
                # It's a file
                $entry
            }
        }

        if ($folderQualifier -match "\/$" -or -not $folderQualifier) {
            $ds = Get-Datastore -Name $Datastore -Server $Server -Verbose:$false
            $dc = Get-VMHost -Datastore $ds -Verbose:$false -Server $Server | Get-Datacenter -Verbose:$false -Server $Server
            $uri = "https://$($Server.Name)/folder$(if($folderQualifier){'/' + $folderQualifier})?dcPath=$($dc.Name)&dsName=$($ds.Name)"
            Write-Verbose "Looking at URI: $($uri)"
            Try {
                $response = Invoke-WebRequest -Uri $Uri -Method Get -Credential $Credential
            } Catch {
                $errorMsg = "`n$(Get-Date -Format 'yyyyMMdd HH:mm:ss') HTTP $($_.Exception.Response.ProtocolVersion)" +
                " $($_.Exception.Response.Method) $($_.Exception.Response.StatusCode.Value__)" +
                " $($_.Exception.Response.StatusDescription)`n" +
                "$(Get-Date -Format 'yyyyMMdd HH:mm:ss') Uri $($_.Exception.Response.ResponseUri)`n "
                Write-Error -Message $errorMsg
                break
            }
            foreach ($entry in $response) {
                $regEx.Matches($entry.Content) |
                Where-Object { $_.Success -and $_.Groups['Filename'].Value -notmatch 'Parent Datacenter|Parent Directory' } | ForEach-Object {
                    Write-Verbose "`tFound $($_.Groups['Filename'].Value)"
                    $fName = $_.Groups['Filename'].Value
                    $obj = [ordered]@{
                        Name      = $_.Groups['Filename'].Value
                        FullName  = "[$($ds.Name)] $($folderQualifier)$(if($folderQualifier -notmatch '/$' -and $folderQualifier){'/'})$($_.Groups['Filename'].Value)"
                        Timestamp = [DateTime]$_.Groups['Timestamp'].Value
                    }
                    if ($fName -notmatch "/$") {
                        $tSize = $_.Groups['Filesize'].Value
                        if ($Unit.IsPresent) {
                            $friendly = $tSize | Get-FriendlyUnit
                            $obj.Add('Size', [Math]::Round($friendly.Value, 0))
                            $obj.Add('Unit', $friendly.Unit)
                        } else {
                            $obj.Add('Size', $tSize)
                        }
                    } else {
                        $obj.Add('Size', '')
                        if ($Unit.IsPresent) {
                            $obj.Add('Unit', '')
                        }
                    }
                    New-Object PSObject -Property $obj
                    if ($_.Groups['Filename'].Value -match "/$" -and $Recurse.IsPresent) {
                        $sDFile = @{
                            Server      = $Server
                            Credential  = $Credential
                            Path        = "[$($ds.Name)] $($folderQualifier)$(if($folderQualifier -notmatch '/$' -and $folderQualifier){'/'})$($_.Groups['Filename'].Value)"
                            Recurse     = $Recurse.IsPresent
                            IncludeRoot = $IncludeRoot
                            Unit        = $Unit.IsPresent
                        }
                        Get-HttpDatastoreItem @sDFile
                    }
                }
            }
        }
        Write-Verbose -Message "$(Get-Date) $($s = Get-PSCallStack;"<Leaving {0}" -f $s[0].FunctionName)"
    }
}
