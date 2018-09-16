Param(
	[Parameter(Mandatory=$true)][string]$Cluster,
    [Parameter(Mandatory=$true)][string]$QOSPolicy,
	[Parameter(Mandatory=$true)][string]$Throughput

)


$Logfilebase = "C:\Scripts\QOSSet_"
$netappusername = 'script'
$netapppasswordfile = 'na_pwd_do_not_delete'

#/Variables
function LogWrite
{
	Param (
	[string]$logstring,
	[string]$severity
	)
	$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
	$Logfilename = $Logfilebase+"0"+".log"
	if ($severity -eq $null -or $severity -eq "INFO" )
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
			write-host "Enter NetApp Cred:"
			Encrypt_password ($passwordfile)
	}
	
	$password = Get-Content $passwordfile | ConvertTo-SecureString 
	$cred = New-Object System.Management.Automation.PsCredential($netappusername,$password)
	$Ctrl = Connect-NcController $filernameSRC -Credential $cred  	
	if (-not $Ctrl) {
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
Connect_Filer -filernameSRC $Cluster #10.61.241.174


#Get Current QOS for QOSPolicy
$Pol=Get-NcQosPolicyGroup -PolicyName $QOSPolicy
LogWrite "Current Max Throughput: $(($Pol).MaxThroughput)"
#Seting QOS max throughtput 
LogWrite "Seting QOS max throughtput to : $($Throughput)"
try
{
	Set-NcQosPolicyGroup -Name $QOSPolicy -MaxThroughput $Throughput -EA stop
}
catch
{
	$ErrorMessage = $_.Exception.Message
	LogWrite "$($ErrorMessage)" -severity ERROR
}
$PolNew=Get-NcQosPolicyGroup -PolicyName $QOSPolicy
LogWrite "New Current Max Throughput: $(($PolNew).MaxThroughput)"
