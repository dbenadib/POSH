###### Dynamic Snapmirror Throttle
###### David BENADIBA
###### 
###### v0.2 (Fix some bugs ;))
###### v0.3 (Don't restore unlimitted throttle)


param([STRING]$DestCluster,[BOOL]$SaveThrottle)
#
function Encrypt_password ($passwordfile)
{
	Write-Host "`nPlease insert a user: $username with his relevant Password" 
	$cred = Get-Credential 
	$cred.Password | ConvertFrom-SecureString | Set-Content $passwordfile
	if (!(Test-Path $passwordfile) ) 
	{
		Write-Host "ERROR: password did not save" 
	}
	else 
	{
		Write-Host "password been hashed and saved to ($passwordfile)" 
	}
}

function Connect_Filer([string]$filernameSRC)
{
	#validate password file exists and convert to PS-Cred object
	#$PSScriptRoot = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
	$passwordfile = "$($PSScriptRoot)\$($netapppasswordfile)"
	$passwordfile_esx = "$($PSScriptRoot)\$($esxpasswordfile)"
	
	if (!(Test-Path $passwordfile)) 
	{
			#write-host "Encrypting NetApp Creds"
			write-host "Enter NetApp Cred:"
			Encrypt_password ($passwordfile)
	}
	if (!(Test-Path $passwordfile_esx)) 
	{
			#write-host "Encrypting ESXi Creds"
			write-host "Enter ESXi Cred:"
			Encrypt_password ($passwordfile_esx)
	}
	$password = Get-Content $passwordfile | ConvertTo-SecureString 
	$cred = New-Object System.Management.Automation.PsCredential($netappusername,$password)
	$Ctrl = Connect-NcController $filernameSRC -Credential $cred
	
	if (-not $Ctrl) {
			Write-Host "ERROR: could not connect to NetApp controller: $filernameSRC" 
	}  
}

function LogRotate()
{
	# Remove Old Reports                  
    Get-ChildItem -literalpath $CheckReportdir -Recurse  | WHERE {($_.name -eq "SMSpeed_recent.txt" )}| Rename-Item -NewName {$_.name -replace "recent",$REPORTdate}
}

#Variable (Must feet your environment)
$CheckReportdir = "C:\test\"
$ThrottleFile="C:\test\SMSpeed_recent.txt" #Forlder can change but file must be SMSpeed_recent.txt
$netappusername = 'admin'
$netapppasswordfile = 'na_pwd_do_not_delete'

#Roll up log file
$REPORTdate = (get-date).AddDays(-1).ToString("MM-dd-yyyy")

#Main 
Connect_Filer -filernameSRC $DestCluster

	
$SMs=get-ncsnapmirror
$StartDate=GET-DATE -format HH:mm:ss
$EndDate=[datetime]'21:00:00'
$Runtime=NEW-TIMESPAN -Start $StartDate -End $EndDate

if ($SaveThrottle) # Get throttle and log in file text
{
	LogRotate
	write "SourceLocation;DestinationLocation;MaxTransferRate" |out-file -filepath $ThrottleFile -Append
	[INT]$count='0'
	foreach ($SM in $SMs)
	{
		write "$($SM.SourceLocation);$($SM.DestinationLocation);$($SM.MaxTransferRate)" |out-file -filepath $ThrottleFile -Append
		$count++
	}
	write-host "Saved throttle configuration of $($count) relationships "
}
else  
{
	if ($Runtime.minutes -gt 0)
	{
		write-host "################"
		write-host "##Set throttle##" -foregroundcolor RED
		write-host "################"
		$SMsInfo=Import-Csv $ThrottleFile -Delimiter ";"
		foreach($SMInfo in $SMsInfo)
		{
			if ($SMInfo.MaxTransferRate -ne "0")
			{
				write-host "Setting throttle of $($SMInfo.MaxTransferRate) kb to Relationship $($SMInfo.DestinationLocation)" -foregroundcolor Green
				Set-NcSnapmirror -DestinationLocation $SMInfo.DestinationLocation -MaxTransferRate $SMInfo.MaxTransferRate|out-null
			}
			else 
			{
				write-host "Relationship $($SMInfo.DestinationLocation) is using unlimitted throttle" -foregroundcolor YELLOW
			}
		}
	}
	else
	{
		write-host "################"
		write-host "##Run Full Gaz##" -foregroundcolor RED
		write-host "################"
		# Run Full Gaz
		foreach ($SM in $SMs)
		{
			$Status=get-ncsnapmirror -DestinationLocation $SM.DestinationLocation
			Set-NcSnapmirror -DestinationLocation $SM.DestinationLocation -MaxTransferRate 0
			if ($Status.RelationshipStatus -eq "Transferring")
			{
				write-host "$($SM) is in transfering status and gonna be aborted then restarted"  -foregroundcolor YELLOW
				Invoke-NcSnapmirrorAbort -DestinationLocation $SM.DestinationLocation
				Start-Sleep -s 25
				Invoke-NcSnapmirrorUpdate -DestinationLocation $SM.DestinationLocation
			}
		}
	}
}

