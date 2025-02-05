############################################################################################
# SETUP: Need to install Pure's PoSH Module
# https://support.purestorage.com/Solutions/Microsoft_Platform_Guide/a_Windows_PowerShell/Install_PowerShell_SDK_using_the_PowerShell_Gallery
# 
# Install-Module -Name PureStoragePowerShellSDK
# Install-Module -Name PureStoragePowerShellSDK2
############################################################################################
Import-Module PureStoragePowerShellSDK

# Refresh a dev database in a few seconds!
$TargetVM = 'ayun-sql19-02.fsa.lab'
$TargetVMSession = New-PSSession -ComputerName $TargetVM
Import-Module SQLPS -PSSession $TargetVMSession -DisableNameChecking
# Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk }    # Find serial numbers

#####
Write-Host "Actual development instance downtime begins now." -ForegroundColor Red

# Offline the database
Write-Host "Offlining the database..." -ForegroundColor Red
$Query = "ALTER DATABASE AdventureWorks2016_EXT SET OFFLINE WITH ROLLBACK IMMEDIATE"
Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

# Offline the volume
# use Get-Disk on the target server, to get your volume's serial number. 
Write-Host "Offlining the volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c2999fd29fad698094ee9b853c8b' } | Set-Disk -IsOffline $True }

# Connect to the FlashArray's REST API, get a session going
Write-Host "Establishing a session against the Pure Storage FlashArray..." -ForegroundColor Red
$FlashArray = New-PfaArray –EndPoint 'sn1-m70r2-f07-27.puretec.purestorage.com' -UserName ayun -IgnoreCertificateError

# Perform the volume overwrite (no intermediate snapshot needed!)
# NOTE the -Overwrite parameter
# Substitute in your vVol names for -VolumeName and -Source
Write-Host "Overwriting the dev instance's volume with a fresh copy from production..." -ForegroundColor Red
New-PfaVolume -Array $FlashArray -VolumeName 'vvol-ayun-sql19-02-4bb08991-vg/AdvWrks' -Source 'vvol-ayun-sql2019-01-91cda082-vg/AdvWks' -Overwrite

# Online the volume
Write-Host "Onlining the volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c2999fd29fad698094ee9b853c8b' } | Set-Disk -IsOffline $False }

# Online the database
Write-Host "Onlining the database..." -ForegroundColor Red
$Query = "ALTER DATABASE AdventureWorks2016_EXT SET ONLINE WITH ROLLBACK IMMEDIATE"
Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

Write-Host "Development database downtime ended." -ForegroundColor Red

# Clean up
Remove-PSSession $TargetVMSession
Write-Host "All done." -ForegroundColor Red