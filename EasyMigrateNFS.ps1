Param(
	[Parameter(Mandatory=$true)][string]$Cluster,
    [Parameter(Mandatory=$true)][string]$Vserver
)

$Logfilebase = "C:\Scripts\NFS_Bkp_"
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

$vols= get-ncvol -Vserver $Vserver
$NFSServer = Get-NcNfsService
$NFSExportPolicy = Get-NcExportPolicy
$NFSExportPolicyRule = Get-NcExportRule
$NFSUnixUser = Get-NcNameMappingUnixUser
$NFSUnixGroup = Get-NcNameMappingUnixGroup
$Qtrees=Get-NcQtree -VserverContext $Vserver

$outname_share="NFS_Exports-Rules_"+$Vserver+".txt"
$outname_Volumes="Volume_To_Create_"+$Vserver+".txt"

write "##################################" | Out-File -FilePath $outname_share -Encoding ascii -Append
write "##################################" | Out-File -FilePath $outname_Volumes -Encoding ascii -Append

#Create Export-Policy
LogWrite "##################"
LogWrite "Creation of Export Policy"
foreach ($vol in $vols)
{

    $ExportPol=$vol.VolumeExportAttributes.policy
    $ExportPolRuls=$NFSExportPolicyRule |?{$_.PolicyName -eq $ExportPol -and $_.vserver -eq $Vserver}
    write "####### Volume: $($vol.name) ##### Export-policy : $($ExportPol)" | Out-File -FilePath $outname_share -Encoding ascii -Append
    write "export-policy create -vserver $($vol.vserver) -policyname $($ExportPol)" | Out-File -FilePath $outname_share -Encoding ascii -Append
    foreach ($EPRule in $ExportPolRuls)
    {
         write "export-policy rule create -vserver $($vol.vserver) -policyname $($ExportPol) -clientmatch $($EPRule.ClientMatch) -ruleindex $($EPRule.RuleIndex) -protocol $($EPRule.Protocol) -rorule $($EPRule.RoRule) -rwrule $($EPRule.rwrule) -anon $($EPRule.AnonymousUserId) -superuser $($EPRule.SuperUserSecurity) -allow-suid $($EPRule.IsAllowSetUidEnabled)" | Out-File -FilePath $outname_share -Encoding ascii -Append
    }
    #Search Qtree
    $QtVol=$Qtrees |?{$_.volume -eq $vol.name -and $_.qtree -ne $null}
    foreach($qt in $QtVol)
    {
        
        write "####### Qtree: $($qt.Qtree) ##### Export-policy : $($qt.ExportPolicy)" | Out-File -FilePath $outname_share -Encoding ascii -Append
        write "export-policy create -vserver $($qt.vserver) -policyname $($qt.ExportPolicy)" | Out-File -FilePath $outname_share -Encoding ascii -Append
        $ExportQtPol=$qt.ExportPolicy
        $ExportQtPolRuls=$NFSExportPolicyRule |?{$_.PolicyName -eq $ExportQtPol -and $_.vserver -eq $Vserver}
        foreach ($EPRule in $ExportQtPolRuls)
        {
            write "export-policy rule create -vserver $($vol.vserver) -policyname $($ExportPol) -clientmatch $($EPRule.ClientMatch) -ruleindex $($EPRule.RuleIndex) -protocol $($EPRule.Protocol) -rorule $($EPRule.RoRule) -rwrule $($EPRule.rwrule) -anon $($EPRule.AnonymousUserId) -superuser $($EPRule.SuperUserSecurity) -allow-suid $($EPRule.IsAllowSetUidEnabled)" | Out-File -FilePath $outname_share -Encoding ascii -Append
        }
    }
    $space=[math]::round($vol.VolumeSpaceAttributes.Size/1MB,0)
    write "vol create -vserver $($vol.vserver) -volume $($vol.name) -aggregate $($vol.aggregate) -size $($space)m -state online -policy $($vol.VolumeExportAttributes.policy) -security-style $($vol.VolumeSecurityAttributes.Style)  -junction-path $($vol.JunctionPath) -space-guarantee $($vol.VolumeSpaceAttributes.SpaceGuarantee) -language $($vol.VolumeLanguageAttributes.LanguageCode)" | Out-File -FilePath $outname_Volumes -Encoding ascii -Append
    #qtree exportPolicy
    if($QtVol)
    {
        foreach($qt in $QtVol)
        {
            write "qtree modify -vserver $($Vserver) -volume $($qt.Volume) -qtree $($qt.Qtree) -export-policy $($qt.ExportPolicy)" | Out-File -FilePath $outname_Volumes -Encoding ascii -Append
        }
    }
}

