############################################################################################
# SETUP: Need to install Pure's PoSH Module
# https://support.purestorage.com/Solutions/Microsoft_Platform_Guide/a_Windows_PowerShell/Install_PowerShell_SDK_using_the_PowerShell_Gallery
# 
# Install-Module -Name PureStoragePowerShellSDK2
# Set-PSSessionConfiguration -ShowSecurityDescriptorUI -Name Microsoft.PowerShell
#
# Values we need ahead of time
# For each TargetVM: 
#    * Databases to offline
#    * Disk Serial Numbers to offline
#    * Virtual Volumes to overlay
#
############################################################################################

# Define variables
$FlashArrayEndPoint = 'sn1-m70-f06-33.puretec.purestorage.com'   # FQDN or IP of the FlashArray that the SQL Server resides on
$DatabaseName = 'FT_Demo_Q'
$SourceVolume = 'vvol-ayun-sql19-01-65d78618-vg/Data-705c9b64'
$SourceProtectionGroup = 'ayun-sql19-01-pg'

# Hashtables Example: (server name - disk serial number; vvol volume name)
$ServersToRefresh = @{
    'ayun-sql19-02.fsa.lab' = ('6000c290a5e609ce391d59ba4764836e', 'vvol-ayun-sql19-02-0ba643d7-vg/Data-bd7cf3d8');
    'ayun-sql19-03.fsa.lab' = ('6000c2924e65d1e5d1a10a68a73aa6f4', 'vvol-ayun-sql19-03-1-cb3ea5b3-vg/Data-ab4f66f1');
    'ayun-sql19-04.fsa.lab' = ('6000c29f150bc61f46da562b6a5eb9d4', 'vvol-ayun-sql19-04-1840d7db-vg/Data-803cc0cd')
}

# Get FSA Lab credentials previously saved via Export-CliXml
$FSALabCredentials = Import-CliXml -Path "${env:\userprofile}\AYun_FSALab.Cred"

# Import Pure Storage PowerShell SDK2
Import-Module PureStoragePowerShellSDK2


#####
Write-Host "Actual development instance downtime begins now." -ForegroundColor Red

# Connect to the FlashArray's REST API, get a session going
Write-Host "Establishing a session against the Pure Storage FlashArray..." -ForegroundColor Red
$FlashArray = Connect-Pfa2Array -Endpoint $FlashArrayEndPoint -Credential ($FSALabCredentials) -IgnoreCertificateError

# Take a Protection Group Snapshot
Write-Host "Taking fresh Protection Group Snapshot" -ForegroundColor Red
$NewPGroupSnapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceNames $SourceProtectionGroup -ApplyRetention $true
Write-Host "Protection Group Snapshot = " $NewPGroupSnapshot.Name " | Created = " $NewPGroupSnapshot.Created

# Loop through Servers to Refresh VMs
ForEach ($TargetVM in $ServersToRefresh.Keys) 
{
    Write-Host '----------'
    Write-Host "TargetVM = $TargetVM"
    Write-Host "Serial Number = $($ServersToRefresh[$TargetVM][0])"
    Write-Host "Target Volume = $($ServersToRefresh[$TargetVM][1])"
    $DiskSerialNumber = $($ServersToRefresh[$TargetVM][0])
    $TargetVolume = $($ServersToRefresh[$TargetVM][1])

    # Start PS session on Server to Refresh
    $TargetVMSession = New-PSSession -ComputerName $TargetVM -Credential $FSALabCredentials
    Import-Module SQLPS -PSSession $TargetVMSession -DisableNameChecking

    # Offline the database
    Write-Host "Offlining the database..." -ForegroundColor Red
    $Query = "ALTER DATABASE [$DatabaseName] SET OFFLINE WITH ROLLBACK IMMEDIATE;"
    Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

    # Offline the volume
    Write-Host "Offlining the volume..." -ForegroundColor Red
    Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | Where-Object { $_.SerialNumber -eq $Using:DiskSerialNumber } | Set-Disk -IsOffline $True }
    
    # Clone the volume(s) from the Protection Group snapshot
    Write-Warning "Overwriting the target database volumes with a copies of the volumes in the most recent snapshot..." 
    New-Pfa2Volume -Array $FlashArray -Name $TargetVolume -SourceName ($NewPGroupSnapshot.Name + '.' + $SourceVolume) -Overwrite $True
    Write-Host "Snapshot clone to volume completed..."

    # Online the volume
    Write-Host "Onlining the volume..." -ForegroundColor Red
    Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | Where-Object { $_.SerialNumber -eq $Using:DiskSerialNumber } | Set-Disk -IsOffline $False }

    # Online the database
    Write-Host "Onlining the database..." -ForegroundColor Red
    $Query = "ALTER DATABASE [$DatabaseName] SET ONLINE WITH ROLLBACK IMMEDIATE"
    Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

    # Close PS session
    Remove-PSSession $TargetVMSession

}

Write-Host "Development database downtime ended." -ForegroundColor Red

# Clean up
Write-Host "All done." -ForegroundColor Red