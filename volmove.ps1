Param(
	[Parameter(Mandatory=$true)][string]$Cluster,
    [Parameter(Mandatory=$true)][string]$SrcAggr,
	[Parameter(Mandatory=$true)][string]$DestAggr
)
#Variables
$Logfilebase = "C:\Scripts\VolMove_"
$netappusername = 'admin'
$netapppasswordfile = 'na_pwd_do_not_delete'
[INT]$PercentFreeOnDestAggr='10' #Minimum Percent free space on destination aggregate 
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
Connect_Filer -filernameSRC $Cluster 

$vols = Get-NcVol -Aggregate $SrcAggr
foreach ($vol in $vols)
{
	LogWrite "Starting vol Move for volume $vol to aggregate $DestAggr"
	LogWrite "Checking if there is enough free space in the aggregate "
	#Checking Aggregate free space
	$DestAggrDetails=Get-NcAggr -Aggr $DestAggr
	$UsedSize=[math]::Round(($vol).VolumeSpaceAttributes.SizeUsed/1GB)
	$AggrFreeSpace=[math]::Round($DestAggrDetails.Available /1GB)
	#Calculating free space adding volume used space
	$FutureAggrFreeSpace=$AggrFreeSpace - $UsedSize
	$FutureAggrUsedSpace=[math]::Round($DestAggrDetails.TotalSize/1GB) - $FutureAggrFreeSpace
	$FuturePercentFreeSpace=100 - ($FutureAggrUsedSpace * 100 / [math]::Round($DestAggrDetails.TotalSize/1GB))
	Logwrite "===INFO==== :  FutureAggrFreeSpace : $FutureAggrFreeSpace ---- FutureAggrUsedSpace: $FutureAggrUsedSpace ----- FuturePercentFreeSpace: $FuturePercentFreeSpace"
	#Validate that Percent free Space is upper than User threshold
	if([math]::Round($FuturePercentFreeSpace) -gt $PercentFreeOnDestAggr)
	{
		LogWrite "Future free space is lower than max Aggregate percent free space threshold : $PercentFreeOnDestAggr"
		LogWrite "== Processing with vol move of volume $vol from aggregate $SrcAggr to $DestAggr =="
		Start-NcVolMove -Name $vol.name -DestinationAggregate $DestAggr -Vserver $vol.vserver |out-null 
		$Started=$true
		while ($Started)
		{
			$volmove=get-ncvolmove -Volume $vol.name
			if ($volmove.state -ne "done")
			{
				Logwrite "Vol Move in progress going to wait for a bit..."
				start-sleep 30
			}
			else
			{
				$Started=$false
				Logwrite "vol move finished !!!!"
			}
		}
	}
	else 
	{
		LogWrite "Future disk usage is greater than User threshold : $PercentFreeOnDestAggr" -severity ERROR
		LogWrite "Consider moving volumes to another aggregate"  -severity ERROR
		exit
	}
}
