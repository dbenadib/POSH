Param(
	[Parameter(Mandatory=$true)][string]$Cluster,
    [Parameter(Mandatory=$true)][string]$Vserver
)

$Logfilebase = "C:\Scripts\CIFS_Bkp_"
$netappusername = 'admin'
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
Connect_Filer -filernameSRC $Cluster #10.61.241.174

#get mount points
$vols= get-ncvol -Vserver $Vserver
#Get list of all cifs shares
$CIFSShares=get-nccifsshare -VserverContext $Vserver |?{$_.ShareName -ne "C$" -and $_.ShareName -ne "IPC$" -and $_.ShareName -ne "admin$" }
#Get ACLS
$CIFSACL=Get-NcCifsShareAcl -VserverContext $Vserver |?{$_.ShareName -ne "C$" -and $_.ShareName -ne "IPC$" -and $_.ShareName -ne "admin$" }
#create outputfilename
$outname_share="Cifs_Shares_"+$vserver+".txt"
$outname_ACL="Cifs_ACL_"+$vserver+".txt"

write "##################################" | Out-File -FilePath $outname_share -Encoding ascii -Append
write "##################################" | Out-File -FilePath $outname_ACL -Encoding ascii -Append

#Generate Comands for Cifs shares
foreach ($Share in $CIFSShares)
{
	#convert $($Share.ShareProperties) to comma separated string
	write "### $($Share.sharename)" | Out-File -FilePath $outname_share -Encoding ascii -Append
	write "### $($Share.sharename)" | Out-File -FilePath $outname_ACL -Encoding ascii -Append
    $prop=($Share.ShareProperties) -join ","
    write "cifs share create -vserver $($vserver) -share-name $($Share.sharename) -share-properties $prop -path $($Share.path) -vscan-fileop-profile $($Share.VscanFileopProfile)" | Out-File -FilePath $outname_share -Encoding ascii -Append
    #Get ACLs for this share
    #Remove default Everyone ACL
    write "cifs share access-control delete -vserver $($vserver) -share $($Share.sharename) -user-or-group Everyone -user-group-type windows" | Out-File -FilePath $outname_ACL -Encoding ascii -Append
    $ACLs=$CIFSACL |?{$_.share -eq $Share.sharename}
    foreach ($ACL in $ACLs)
    {
        write "cifs share access-control create -vserver $($ACL.vserver)  -share $($ACL.Share) -user-or-group $($ACL.UserOrGroup) -user-group-type $($ACL.UserGroupType) -permission $($ACL.Permission)" | Out-File -FilePath $outname_ACL -Encoding ascii -Append
    }
}

