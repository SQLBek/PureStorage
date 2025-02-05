##############################################################################################################################
# Modification of Refresh-Dev-ProtectionGroups-vVol.ps1 for use with VMware vVols based SQL VMs                 #
##############################################################################################################################

# Variables Section
$PGroupName        = 'sn1-m70-f06-33:003ProdSQL-Gold'                     # Protection Group Name 
$FAEndPoint        = 'sn1-x70-f06-27.puretec.purestorage.com'               # FQDN or IP of the FlashArray that the SQL Server resides on

# Name(s) of the SQL database(s) to take offline
$databases     = @('AutoDealershipDemo','CookbookDemo','Sandbox')

# Corresponding Source SQL VM vVols that are going to be used to overwrite the targets
$SourceVolumes = @('vvol-MUTTDB001-bd7156db-vg/Data-e7199a87', 'vvol-MUTTDB001-bd7156db-vg/Data-336fbfed')

# Ensure that the array position of the targetvolume, targetdevice, & sourcedevice match
# Name(s) of the Target SQL VM vVols that are going to be overwritten
$TargetServer = 'MUTTDB003'                        # Configure the target SQL Server 
$TargetVolumes = @('vvol-MUTTDB003-48e1f033-vg/Data-4ecf377e', 'vvol-MUTTDB003-48e1f033-vg/Data-5cd0c4d8')
$TargetDevices = @('6000c29bfc9bc831cece06d8ed77fad4', '6000c295a7ab7afd0e78ee553865a84b')                            # Target Device ID(s)


###########################################################
# It should not be necessary to make any changes below    #
###########################################################
Import-Module PureStoragePowerShellSDK2 -DisableNameChecking

# Create a session to the target server
$TargetServerSession = New-PSSession -ComputerName $TargetServer

# Import the SQLPS module so SQL commands are available
Import-Module SQLPS -PSSession $TargetServerSession -DisableNameChecking


###
# Offline the database(s)
Write-Warning "Offlining the target database(s)..."
Foreach ($database in $databases) {
    Write-Host "Offlining $database"

    # Offline the database
    Write-Warning "Offlining the target database..."
    $Query = "ALTER DATABASE " + $($database) + " SET OFFLINE WITH ROLLBACK IMMEDIATE"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)
}

# Offline the volumes that have SQL data
Write-Warning "Offlining the target volume(s)..." 
Foreach ($targetdevice in $TargetDevices) {
    Write-Host "Offlining Disk $($targetdevice)"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($currentdisk) Get-Disk | ? { $_.SerialNumber -eq $($currentdisk) } | Set-Disk -IsOffline $True } -ArgumentList ($targetdevice)
}


###
# Connect to the FlashArray's REST API, get a session going
Write-Warning "Establishing a session against the Pure Storage FlashArray..." 
$FACredential = Get-Credential -UserName "ayun" -Message 'Enter your FlashArray credential information...'
$FlashArray = Connect-Pfa2Array -Endpoint $FAEndPoint -Credential ($FACredential) -IgnoreCertificateError


###
# Get the most recent snapshot; could also use code to select among a list of prior snapshots
# Could also take a new protection group snapshot instead of using a scheduled one: via UI or code
Write-Host "Obtaining the most recent snapshot for the protection group..." -ForegroundColor Red
$MostRecentSnapshots = Get-Pfa2ProtectionGroupSnapshot -Array $FlashArray -Name $PGroupName | Sort-Object created -Descending | Select-Object -Property name -First 5
$MostRecentSnapshots 

###
# Check that the last snapshot has been fully replicated
$FirstSnapStatus = Get-Pfa2ProtectionGroupSnapshotTransfer  -Array $FlashArray -Name $MostRecentSnapshots[0].name
# If the latest snapshot's completed property is null, then it hasn't been fully replicated - the previous snapshot is good, though
if ($FirstSnapStatus.completed -ne $null) {
    $MostRecentSnapshot = $MostRecentSnapshots[0].name
}
else {
    $MostRecentSnapshot = $MostRecentSnapshots[1].name
}

Write-Warning "Will use this snapshot for the overwrite..." 
$MostRecentSnapshot


###
# Perform the target volume(s) overwrite
Write-Warning "Overwriting the target database volumes with a copies of the volumes in the most recent snapshot..." 
Foreach ($targetvolume in $TargetVolumes) {
    $SourceVolume = $MostRecentSnapshot + "." + $SourceVolumes[$TargetVolumes.IndexOf($targetvolume)]
    New-Pfa2Volume -Array $FlashArray -Name $targetvolume -SourceName $SourceVolume -Overwrite $true
}


###
# Online the volume(s)
Write-Warning "Onlining the target volumes..." 
Foreach ($targetdevice in $TargetDevices) {
    Write-Host "Onlining Disk $($targetdevice)"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($currentdisk) Get-Disk | ? { $_.SerialNumber -eq $($currentdisk) } | Set-Disk -IsOffline $False } -ArgumentList ($targetdevice)
}

Write-Warning "Force Read-Write on the target volumes..." 
Foreach ($targetdevice in $TargetDevices) {
    Write-Host "Onlining Disk $($targetdevice)"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($currentdisk) Get-Disk | ? { $_.SerialNumber -eq $($currentdisk) } | Set-Disk -IsReadOnly $False } -ArgumentList ($targetdevice)
}

# Online the database
Foreach ($database in $databases) {
    Write-Host "Onlining $database"
    $Query = "ALTER DATABASE " + $($database) + " SET ONLINE WITH ROLLBACK IMMEDIATE"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)
}

# Give an update
Write-Warning "Target database downtime ended." 

# Clean up
Remove-PSSession $TargetServerSession

Write-Warning "All done."

