$Title = "VSAN Datastore Capacity"
$Comments = "Uses a 25% free-space alert aligned with vSAN operations guidance for rebuild/slack space (see: <a href='https://blogs.vmware.com/cloud-foundation/2021/12/11/revisiting-vsans-free-capacity-recommendations/' target='_blank'>Revisiting vSAN’s Free Capacity Recommendations</a>)."
$Display = "Table"
$Author = "William Lam, Alan Renouf & Jonathan Medd"
$PluginVersion = 1.2
$PluginCategory = "vSphere"

# Start of Settings 
# Set the warning threshold for VSAN Datastore % Free Space (operational best-practice, not a hard maximum)
$DatastoreSpace = 25
# End of Settings

# Update settings where there is an override
$DatastoreSpace = Get-vCheckSetting $Title "DatastoreSpace" $DatastoreSpace

$Datastores | Where-Object { $_.Type -match 'vsan' } | Select-Object Name, Type, 
@{N = "CapacityGB"; E = { [math]::Round($_.CapacityGB, 2) } },
@{N = "ProvisionedGB"; E = { ([math]::Round($_.CapacityGB, 2) - [math]::Round($_.FreeSpaceGB, 2)) } },
@{N = "FreeSpaceGB"; E = { [math]::Round($_.FreeSpaceGB, 2) } }, PercentFree | Sort-Object PercentFree | Where-Object { $_.PercentFree -lt $DatastoreSpace }

$Header = "VSAN Datastores (Less than $DatastoreSpace% Free) : [count]"

$TableFormat = @{"PercentFree" = @(@{ "-le 15" = "Row,class|warning"; },
      @{ "-le 10" = "Row,class|critical" })
   "CapacityGB"                = @(@{ "-lt 499.75" = "Cell,style|background-color: #FFDDDD" })
}
                
# Change Log
## 1.0 : Initial version
## 1.1 : Code refactor
## 1.2 : Raise free-space alert to 25% and link to vSAN free capacity guidance blog