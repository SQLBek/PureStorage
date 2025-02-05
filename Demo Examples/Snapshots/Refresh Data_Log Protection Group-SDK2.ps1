##############################################################################################################################
# Modification of Refresh-Dev-ProtectionGroups-vVol.ps1 for use with VMware vVols based SQL VMs                 #
#
##############################################################################################################################

# Variables Section
$PGroupName        = 'ayun-sql19-01-pg'                     # Protection Group Name 
$FAEndPoint        = 'sn1-x90r2-f06-33.puretec.purestorage.com'   # FQDN or IP of the FlashArray that the SQL Server resides on

# Name(s) of the SQL database(s) to take offline
$databases     = @('AutoDealershipDemo','CookbookDemo','Sandbox')

# Corresponding Source SQL VM vVols that are going to be used to overwrite the targets
$SourceVolumes = @('vvol-ayun-sql19-01-65d78618-vg/D_Data','vvol-ayun-sql19-01-65d78618-vg/L_Log')

# Ensure that the array position of the targetvolume, targetdevice, & sourcedevice match
# Name(s) of the Target SQL VM vVols that are going to be overwritten         
$TargetServer = 'ayun-sql19-02'                        # Configure the target SQL Server 
$TargetVolumes = @('vvol-ayun-sql19-02-1-9b1e8075-vg/D_Data','vvol-ayun-sql19-02-1-9b1e8075-vg/L_Log')
$TargetDevices = @('6000c298da5843894d4bf4d05806c274', '6000c29400f23966394ce547f862610d')                            # Target Device ID(s)


###########################################################
# It should not be necessary to make any changes below    #
###########################################################
Import-Module PureStoragePowerShellSDK2 -DisableNameChecking

# Create a session to the target server
$TargetServerSession = New-PSSession -ComputerName $TargetServer

# Import the SQLPS module so SQL commands are available
Import-Module SQLPS -PSSession $TargetServerSession -DisableNameChecking


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


# Connect to the FlashArray's REST API, get a session going
Write-Warning "Establishing a session against the Pure Storage FlashArray..." 
$FACredential = Get-Credential -UserName "ayun" -Message 'Enter your FlashArray credential information...'
$FlashArray = Connect-Pfa2Array -Endpoint $FAEndPoint -Credential ($FACredential) -IgnoreCertificateError


# Create a fresh snapshot of the Protection Group
Write-Warning "Creating a new snapshot of the Protection Group..."
$MostRecentSnapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceNames 'ayun-sql19-01-pg' -ApplyRetention $true
$MostRecentSnapshot


# OPTIONAL: Get the most recent snapshot; could also use code to select among a list of prior snapshots
# List recent snapshots
# Get-Pfa2ProtectionGroupSnapshot -Array $FlashArray -Name $PGroupName | Sort-Object created -Descending | Select -Property name -First 10

# Perform the target volume(s) overwrite
Write-Warning "Overwriting the target database volumes with a copies of the volumes in the most recent snapshot..." 
Foreach ($targetvolume in $TargetVolumes) {
    $SourceVolume = $MostRecentSnapshot.name + "." + $SourceVolumes[$TargetVolumes.IndexOf($targetvolume)]
    New-Pfa2Volume -Array $FlashArray -Name $TargetVolume -SourceName $SourceVolume -Overwrite $true
}

# Online the volume(s)
Write-Warning "Onlining the target volumes..." 
Foreach ($targetdevice in $TargetDevices) {
    Write-Host "Onlining Disk $($targetdevice)"
    Invoke-Command -Session $TargetServerSession -ScriptBlock {Param($currentdisk) Get-Disk | ? { $_.SerialNumber -eq $($currentdisk) } | Set-Disk -IsOffline $False } -ArgumentList ($targetdevice)
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

