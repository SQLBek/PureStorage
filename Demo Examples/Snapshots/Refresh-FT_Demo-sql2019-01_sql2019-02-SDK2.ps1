############################################################################################
# SETUP: Need to install Pure's PoSH Module
# https://support.purestorage.com/Solutions/Microsoft_Platform_Guide/a_Windows_PowerShell/Install_PowerShell_SDK_using_the_PowerShell_Gallery
# 
# Install-Module -Name PureStoragePowerShellSDK2
# Set-PSSessionConfiguration -ShowSecurityDescriptorUI -Name Microsoft.PowerShell
############################################################################################


#####
# Refresh a dev database in a few seconds!
$FACredential = Get-Credential -UserName "ayun" -Message 'Enter your Pure credentials'
$TargetVM = 'ayun-sql19-02.fsa.lab'
$TargetVMSession = New-PSSession -ComputerName $TargetVM -Credential $FACredential
Import-Module SQLPS -PSSession $TargetVMSession -DisableNameChecking
Import-Module PureStoragePowerShellSDK2

#####
Write-Host "Actual development instance downtime begins now." -ForegroundColor Red

# Offline the database
Write-Host "Offlining the database..." -ForegroundColor Red
$Query = "ALTER DATABASE FT_Demo SET OFFLINE WITH ROLLBACK IMMEDIATE"
Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

# Offline the volume
Write-Host "Offlining the volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c29506725ad866afd80b73e07d9e' } | Set-Disk -IsOffline $True }

# Connect to the FlashArray's REST API, get a session going
Write-Host "Establishing a session against the Pure Storage FlashArray..." -ForegroundColor Red
$FAEndPoint = 'sn1-x90r2-f06-33.puretec.purestorage.com'   # FQDN or IP of the FlashArray that the SQL Server resides on
$FlashArray = Connect-Pfa2Array -Endpoint $FAEndPoint -Credential ($FACredential) -IgnoreCertificateError

# Take a Protection Group Snapshot
Write-Host "Taking fresh Protection Group Snapshot" -ForegroundColor Red
$NewPGroupSnapshot = New-Pfa2ProtectionGroupSnapshot -Array $FlashArray -SourceNames 'ayun-sql19-01-pg' -ApplyRetention $true
$NewPGroupSnapshot

# Clone the volume(s) from the Protection Group snapshot
Write-Warning "Overwriting the target database volumes with a copies of the volumes in the most recent snapshot..." 
New-Pfa2Volume -Array $FlashArray -Name 'vvol-ayun-sql19-02-0ba643d7-vg/X_FTDemo' -SourceName ($NewPGroupSnapshot.Name + '.vvol-ayun-sql19-01-65d78618-vg/X_FTDemo') -Overwrite $true

# Online the volume
Write-Host "Onlining the volume..." -ForegroundColor Red
Invoke-Command -Session $TargetVMSession -ScriptBlock { Get-Disk | ? { $_.SerialNumber -eq '6000c29506725ad866afd80b73e07d9e' } | Set-Disk -IsOffline $False }

# Online the database
Write-Host "Onlining the database..." -ForegroundColor Red
$Query = "ALTER DATABASE FT_Demo SET ONLINE WITH ROLLBACK IMMEDIATE"
# $Query = "ALTER DATABASE FT_Demo SET ONLINE WITH NO_WAIT"
Invoke-Command -Session $TargetVMSession -ScriptBlock {Param($querytask) Invoke-Sqlcmd -ServerInstance . -Database master -Query $querytask} -ArgumentList ($Query)

Write-Host "Development database downtime ended." -ForegroundColor Red

# Clean up
Remove-PSSession $TargetVMSession
Write-Host "All done." -ForegroundColor Red