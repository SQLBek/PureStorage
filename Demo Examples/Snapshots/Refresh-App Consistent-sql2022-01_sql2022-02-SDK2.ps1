﻿##############################################################################################################################
# Point In Time Recovery - Using SQL Server 2022's T-SQL Snapshot Backup feature 
#
# Scenario: 
#    Perform a point in time restore using SQL Server 2022's T-SQL Snapshot Backup 
#    feature. This uses a FlashArray snapshot as the base of the restore, then restores 
#    a log backup.
#
# Prerequisites:
# 1. A SQL Server running SQL Server 2022 with a database having data files and a log file on two volumes that are each on different FlashArrays.
#
# Usage Notes:
#   Each section of the script is meant to be run one after the other. 
#   The script is not meant to be executed all at once.
#
# Disclaimer:
#    This example script is provided AS-IS and is meant to be a building
#    block to be adapted to fit an individual organization's 
#    infrastructure.
##############################################################################################################################



# Import powershell modules
Import-Module dbatools
Import-Module PureStoragePowerShellSDK2



# Let's initalize some variables we'll use for connections to our SQL Server and it's base OS
$TargetSQLServer   = 'ayun-sql22-01.fsa.lab'                         # SQL Server Name
$ArrayName         = 'sn1-x90r2-f07-27.puretec.purestorage.com'      # FlashArray
$DbName            = 'FT_Demo'                                       # Name of database
$BackupShare       = '\\10.21.200.27\ayun-sql-backups\FTDemo_2022'   # File system location to write the backup metadata file
$PGroupName        = 'ayun-sql22-01-pg'                              # Name of the Protection Group on FlashArray1
$FlashArrayDbVol   = 'vvol-ayun-sql22-01-261d769b-vg/X_FTDemo'       # Volume name on FlashArray containing database files
$TargetDisk        = '6000C29661215A177DC3A5FD63B69597'              # The serial number if the Windows volume containing database files
$ErrorLogTimestamp = (Get-Date).AddMinutes(-10)                      # Used to only retrieve last 10 minutes worth of SQL error log entries



# Build a PowerShell Remoting Session to the Server
$SqlServerSession = New-PSSession -ComputerName $TargetSQLServer



# Build a persistent SMO connection
$SqlInstance = Connect-DbaInstance -SqlInstance $TargetSQLServer -TrustServerCertificate -NonPooledConnection



# Let's get some information about our database, take note of the size
Get-DbaDatabase -SqlInstance $SqlInstance -Database $DbName |
  Select-Object Name, SizeMB



# Connect to the FlashArray's REST API
$Credential = Get-Credential -UserName "ayun" -Message 'Enter your Pure credentials'
$FlashArray = Connect-Pfa2Array –EndPoint $ArrayName -Credential $Credential -IgnoreCertificateError



# Freeze the database
$Query = "ALTER DATABASE $DbName SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON"
Invoke-DbaQuery -SqlInstance $SqlInstance -Query $Query -Verbose



# Take a snapshot of the Protection Group while the database is frozen
$Snapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceNames 'ayun-sql22-01-pg' -ApplyRetention $true
$Snapshot



# Take a metadata backup of the database, this will automatically unfreeze if successful
# We'll use MEDIADESCRIPTION to hold some information about our snapshot and the flasharray its held on
$BackupFile = "$BackupShare\$DbName_$(Get-Date -Format FileDateTime).bkm"
$Query = "BACKUP DATABASE $DbName 
          TO DISK='$BackupFile' 
          WITH METADATA_ONLY, MEDIADESCRIPTION='$($Snapshot.Name)|$($FlashArray.ArrayName)'"
Invoke-DbaQuery -SqlInstance $SqlInstance -Query $Query -Verbose



# Let's check out the error log to see what SQL Server thinks happened
Get-DbaErrorLog -SqlInstance $SqlInstance -LogNumber 0 -After $ErrorLogTimestamp | Format-Table



# The backup is recorded in MSDB as a Full backup with snapshot
$BackupHistory = Get-DbaDbBackupHistory -SqlInstance $SqlInstance -Database $DbName -Last
$BackupHistory



# Let's explore the stuff in the backup header...
# Remember, VDI is just a contract saying what's in the backup matches what SQL Server thinks is in the backup.
Read-DbaBackupHeader -SqlInstance $SqlInstance -Path $BackupFile



# Let's take a log backup
$LogBackup = Backup-DbaDatabase -SqlInstance $SqlInstance -Database $DbName -Type Log -Path $BackupShare -CompressBackup




# Check one of our data tables: dbo.MyStuff
Invoke-DbaQuery -SqlInstance $SqlInstance -Database FT_Demo -Query "SELECT @@SERVERNAME AS ServerName, COUNT(1) AS NumOfRecords, MAX(MyTimestamp) AS TimeStamp FROM FT_Demo.dbo.MyStuff;"



# Delete the dbo.MyStuff table...I should update my resume, right? :P 
Invoke-DbaQuery -SqlInstance $SqlInstance -Database FT_Demo -Query "DROP TABLE dbo.MyStuff;"

Invoke-DbaQuery -SqlInstance $SqlInstance -Database FT_Demo -Query "SELECT @@SERVERNAME AS ServerName, COUNT(1) AS NumOfRecords, MAX(MyTimestamp) AS TimeStamp FROM FT_Demo.dbo.MyStuff;"



# Let's check out the state of the database, size, last full and last log
Get-DbaDatabase -SqlInstance $SqlInstance -Database $DbName | 
  Select-Object Name, Size, LastFullBackup, LastLogBackup



# Offline the database, which we'd have to do anyway if we were restoring a full backup
$Query = "ALTER DATABASE $DbName SET OFFLINE WITH ROLLBACK IMMEDIATE" 
Invoke-DbaQuery -SqlInstance $SqlInstance -Database master -Query $Query



# Offline the volume
Invoke-Command -Session $SqlServerSession -ScriptBlock { Get-Disk | Where-Object { $_.SerialNumber -eq $using:TargetDisk } | Set-Disk -IsOffline $True }



# We can get the snapshot name from the $Snapshot variable above, but what if we didn't know this ahead of time?
# We can also get the snapshot name from the MEDIADESCRIPTION in the backup file. 
$Query = "RESTORE LABELONLY FROM DISK = '$BackupFile'"
$Labels = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $Query -Verbose
$SnapshotName = (($Labels | Select-Object MediaDescription -ExpandProperty MediaDescription).Split('|'))[0]
$ArrayName = (($Labels | Select-Object MediaDescription -ExpandProperty MediaDescription).Split('|'))[1]
$SnapshotName
$ArrayName



# Restore the snapshot over the volume
New-Pfa2Volume -Array $FlashArray -Name $FlashArrayDbVol -SourceName ($SnapshotName + ".$FlashArrayDbVol") -Overwrite $true



# Online the volume
Invoke-Command -Session $SqlServerSession -ScriptBlock { Get-Disk | Where-Object { $_.SerialNumber -eq $using:TargetDisk} | Set-Disk -IsOffline $False }



# Restore the database with no recovery, which means we can restore LOG native SQL Server backups 
$Query = "RESTORE DATABASE $DbName FROM DISK = '$BackupFile' WITH METADATA_ONLY, REPLACE, NORECOVERY" 
Invoke-DbaQuery -SqlInstance $SqlInstance -Database master -Query $Query -Verbose



# Let's check the current state of the database...its RESTORING
Get-DbaDbState -SqlInstance $SqlInstance -Database $DbName 



# Restore the log backup.
Restore-DbaDatabase -SqlInstance $SqlInstance -Database $DbName -Path $LogBackup.BackupPath -NoRecovery -Continue



# Online the database
$Query = "RESTORE DATABASE $DbName WITH RECOVERY" 
Invoke-DbaQuery -SqlInstance $SqlInstance -Database master -Query $Query



# Let's see if our table is back in our database...
# whew...we don't have to tell anybody since our restore was so fast :P 
Invoke-DbaQuery -SqlInstance $SqlInstance -Database FT_Demo -Query "SELECT @@SERVERNAME AS ServerName, COUNT(1) AS NumOfRecords, MAX(MyTimestamp) AS TimeStamp FROM FT_Demo.dbo.MyStuff;"



Break
#####
# How long does this process take, this demo usually takes 450ms? 
# (Make sure to run the setup code up at the top first, if other part of demo was not executed)
$Start = (Get-Date)



# Freeze the database
$Query = "ALTER DATABASE $DbName SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON"
Invoke-DbaQuery -SqlInstance $SqlInstance -Query $Query -Verbose



#Take a snapshot of the Protection Group while the database is frozen
$Snapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceNames $PGroupName
$Snapshot



#Take a metadata backup of the database, this will automatically unfreeze if successful
#We'll use MEDIADESCRIPTION to hold some information about our snapshot
$BackupFile = "$BackupShare\$DbName_$(Get-Date -Format FileDateTime).bkm"
$Query = "BACKUP DATABASE $DbName 
          TO DISK='$BackupFile' 
          WITH METADATA_ONLY, MEDIADESCRIPTION='$($Snapshot.Name)|$($FlashArray.ArrayName)'"
Invoke-DbaQuery -SqlInstance $SqlInstance -Query $Query -Verbose
$Stop = (Get-Date)



Write-Output "The snapshot time takes...$(($Stop - $Start).Milliseconds)ms!"
