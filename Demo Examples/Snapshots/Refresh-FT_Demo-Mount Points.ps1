############################################################################################
# SETUP: Need to install Pure's PoSH Module
# https://support.purestorage.com/Solutions/Microsoft_Platform_Guide/a_Windows_PowerShell/Install_PowerShell_SDK_using_the_PowerShell_Gallery
# 
# Install-Module -Name PureStoragePowerShellSDK2
# Set-PSSessionConfiguration -ShowSecurityDescriptorUI -Name Microsoft.PowerShell
############################################################################################


#Let's initialize some variables we'll use for connections to our SQL Server and it's base OS
$Target = 'aen-sql-22-b'
$TargetSession = New-PSSession -ComputerName $Target
$Credential = Import-CliXml -Path "$HOME\FA_Cred.xml"



# Offline the volumes
# First we remove the access path for the mountpoint, then we offline the exact disk we want to offline
Write-Output "Offlining the target volumes..."
Invoke-Command -Session $TargetSession -ScriptBlock { Remove-PartitionAccessPath -AccessPath 'D:\NONPROD_MOUNTPOINT\' -DiskNumber 6 -PartitionNumber 2 }
Invoke-Command -Session $TargetSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c299c1eefcd1829168f4c44b8ba2' } | Set-Disk -IsOffline $True }


# Connect to the FlashArray's REST API, get a session going
# THIS IS A SAMPLE SCRIPT WE USE FOR DEMOS! _PLEASE_ do not save your password in cleartext here.
# Use NTFS secured, encrypted files or whatever else -- never cleartext!
Write-Output "Establishing a session against the Pure Storage FlashArray..." -ForegroundColor Red
$FlashArray = Connect-Pfa2Array –EndPoint sn1-x90r2-f06-33.puretec.purestorage.com -Credential $Credential -IgnoreCertificateError


# If you don't want a new snapshot of the Protection Group generated whenever you run this script, comment this next line
Write-Output "Creating a new snapshot of the Protection Group..."
$Snapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceName 'aen-sql-22-a-pg'
$Snapshot


# Perform the target volume overwrite
Write-Output "Overwriting the target database volumes with copies of the volumes in the most recent snapshot..."
New-Pfa2Volume -Array $FlashArray -Name 'vvol-aen-sql-22-b-9b9a3477-vg/Data-2246dcfa' -SourceName ($Snapshot.Name + ".vvol-aen-sql-22-a-1-3d9acfdd-vg/Data-38cb941f") -Overwrite $true


# Online the volume
Write-Output "Onlining the target volumes..."
Invoke-Command -Session $TargetSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c299c1eefcd1829168f4c44b8ba2' } | Set-Disk -IsOffline $False }


# You can then use this cmdlet to rename the exact volume and partition to the non-production nam
Invoke-Command -Session $TargetSession -ScriptBlock {
    (Get-Disk -SerialNumber '6000c299c1eefcd1829168f4c44b8ba2' | Get-Partition -Number 2 | Get-Volume) | Set-Volume -NewFileSystemLabel  'NONPROD_MOUNTPOINT' }


# Then we need to add an access path for the new disk and partition. These are hardcoded, but can be parameterized.
Invoke-Command -Session $TargetSession -ScriptBlock { Add-PartitionAccessPath -AccessPath 'D:\NONPROD_MOUNTPOINT\' -DiskNumber 6 -PartitionNumber 2  }