Param(
	[Parameter(Mandatory=$true)][string]$ProdCluster,
	[Parameter(Mandatory=$true)][string]$vserver
)
#Variables
$Logfilebase = "C:\Scripts\Snapmirror_"
$netappusername = 'admin'
$netapppasswordfile = 'na_pwd_do_not_delete'
$outname_volume = "C:\Scripts\VolumeToCreate.txt"
$outname_snapmirror = "C:\Scripts\SnapmirrorToCreate.txt"
#/Variables

function LogWrite
{
	Param (
	[string]$logstring,
	[string]$severity
	)
	$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
	$Logfilename = $Logfilebase+"0"+".log"
	if ($severity -eq "" -or $severity -eq "INFO" )
	{
		Write-Host "`n $($logstring)" 
		"INFO - $LogTime - $logstring" | Out-File $Logfilename -Append -Encoding ASCII
	}
	if ($severity -eq "ERROR")
	{
		Write-Host "`n $($logstring)" -ForegroundColor RED
		"ERROR - $LogTime - $logstring" | Out-File $Logfilename -Append -Encoding ASCII
	}
}
function Connect_Filer([string]$filernameSRC)
{
	#validate password file exists and convert to PS-Cred object
	$passwordfile = "$($PSScriptRoot)\$($netapppasswordfile)"
	if (!(Test-Path $passwordfile)) 
	{
			LogWrite "Encrypting NetApp Creds"
			Encrypt_password ($passwordfile)
	}
	
	$password = Get-Content $passwordfile | ConvertTo-SecureString 
	$cred = New-Object System.Management.Automation.PsCredential($netappusername,$password)
	$Ctrl = Connect-NcController $filernameSRC -Credential $cred  	
	if (-not $Ctrl) 
	{
			LogWrite "ERROR: could not connect to NetApp controller: $filernameSRC" -severity ERROR
			return $false
	} 
	else
	{
		LogWrite "Connected to $($Ctrl)" 
	}	
}
function Encrypt_password ($passwordfile)
{
	Write-Host "`nPlease insert a user: $username with his relevant Password" 
	$cred = Get-Credential 
	$cred.Password | ConvertFrom-SecureString | Set-Content $passwordfile
	if (!(Test-Path $passwordfile) ) 
	{
		LogWrite "ERROR: password did not save" -severity ERROR
	}
	else 
	{
		LogWrite "password been hashed and saved to ($passwordfile)" 
	}
}
LogWrite "####################################################"
Import-Module DataONTAP
Connect_Filer -filernameSRC $ProdCluster 


#Getting list of Data Aggregate
#$DataAggrs=Get-NcAggr  |?{$_.Nodes -eq $Node}|?{$_.AggrRaidAttributes.HasLocalRoot -eq $false} 
write "####### Snapmirror cmds" | Out-File -FilePath $outname_snapmirror -Encoding ascii -Append
write "####### Vol Create cmds" | Out-File -FilePath $outname_snapmirror -Encoding ascii -Append


	$vols = Get-NcVol -Vserver $vserver | ?{$_.VolumeStateAttributes.IsVserverRoot -eq $false}|?{$_.VolumeMirrorAttributes.IsDataProtectionMirror -eq $false}
	foreach ($vol in $vols)
	{
		#Checking if volume are protected or not 
		
			#Volume is not part of a relationship
			LogWrite "Volume: $($vol.name) is not part of Snapmirror Relationship" -severity ERROR
			#Create snapmirror relationship
			#Getting vserver peer 
			$DrpVserver=Get-NcVserverPeer -Vserver $vol.vserver |?{$_.PeerVserver -match "mcc-"}
			write "vol create -volume $($vol.name) -vserver $($DrpVserver.PeerVserver) -type DP -language $($vol.VolumeLanguageAttributes.LanguageCode)" -aggregate  | Out-File -FilePath $outname_volume -Encoding ascii -Append
			write "snapmirror create -source-path $($vol.vserver):$($vol.name) -destination-path $($DrpVserver.PeerVserver):$($vol.name) -type DP -schedule daily" | Out-File -FilePath $outname_snapmirror -Encoding ascii -Append
		
	}
	



