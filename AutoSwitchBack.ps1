#####################
# David BENADIBA    #
#    	 	    	#
# SwitchBack.ps1   	#
#  v 1.0	    	#
#####################
Param(
  [Parameter(Mandatory=$True)]
   [string]$ClusterA,
  [Parameter(Mandatory=$True)]
   [string]$ClusterB,
  [Parameter(Mandatory=$True)]
   [string]$SPA,
  [Parameter(Mandatory=$True)]
   [string]$SPB,
  [Parameter(Mandatory=$False)]
   [switch]$HumanInteraction,
  [Parameter(Mandatory=$False)]
   [switch]$ValidateEntries)

function Import-PoshModule
{
	if (Get-Module -Name "Posh-SSH") 
	{
		Write-Host "SSH PowerShell Module exists" -foregroundcolor Green
	}	 
	else 
	{
		write-host "Importing Module ... " -foregroundcolor Yellow
		import-module .\ssh\Posh-SSH\Posh-SSH.psd1
		get-module -name "Posh-SSH"
	}
}

function Connect_SP([string]$SPIP)
{
	#validate password file exists and convert to PS-Cred object
	if (!(Test-Path $passwordfile)) 
	{
			LogWrite "Password Encryption for SP"
			write-host "Enter SP Cred:"
			Encrypt_password ($passwordfile)
			$passwordfile
			
	}
	$password = Get-Content $passwordfile | ConvertTo-SecureString 
	$cred = New-Object System.Management.Automation.PsCredential($SPusername,$password)
	New-SshSession -ComputerName $SPIP -Credential $cred  -ConnectionTimeout 60 |out-null
	$session=get-sshsession 
	if (-not $session) {
			Write-Host "ERROR: could not connect to SP " -foregroundcolor red
			Logwrite "Could not connect to SP - Error connection using SSH"
			return $false
	} 
	else
	{
		$Global:SSHStream = New-SSHShellStream -Index 0
	}
}

function Close-SSHSession
{
	$Sessions=Get-SSHSession
	foreach ($Session in $Sessions)
	{
		Remove-SSHSession -SessionId $Session.SessionId |out-null
	}
	$Global:SSHStream=$null
}

function LogWrite
{
	Param ([string]$logstring)
	$LogTime = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"
	$Logfilename = $Logfilebase+"0"+".log"
	"$LogTime - $logstring" | Out-File $Logfilename -Append -Encoding ASCII

	if ((Get-Item $Logfilename).Length -gt $maxlogfilesize) 
	{
		$lastlog = "$Logfilebase${maxlogfiles}"
		if (Test-Path $Logfilebase${maxlogfiles}) 
		{
			Remove-Item -Path $lastlog
		}
		for ($i=$maxlogfiles-1; $i -ge 0; $i--) 
		{
			if (Test-Path $Logfilebase${i}) 
			{
				$j = $i + 1 
				Rename-Item $Logfilebase${i} $Logfilebase${j}
			}
		}
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
			Write-Host "ERROR: could not connect to NetApp controller: $filernameSRC" 
			return $false
	}  
}

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

function SwitchBack 
{
	 write-host "Running Switchback in simulation mode" -foregroundcolor YELLOW
	 LogWrite "Running Switchback in simulation mode"
	 $SBop=Invoke-NcMetroclusterSwitchback -Simulate -confirm:$false
	 sleep 5
	 $c='1'
	while ($c -eq '1')
	{
		#$SBop
		$op=Get-NcMetroclusterOperation -operation "switchback_simulate" |?{$_.JobID -eq $SBop.JobID}
		if ($op.State -eq "successful")
		{
			$c='0'
			LogWrite "Simualtion succeded. Running switchback now!!"
			write-host "Running Switchback..." -foregroundcolor GREEN
			Mailer -subject "Simualtion succeded. Running switchback now!!"
			Invoke-NcMetroclusterSwitchback -confirm:$false
			return $true
		}
		if ($op.State -eq "in_progress")
		{
			write-host "Simulation is still in progress. Rechecking in 5 sec"
			LogWrite "Simulation is still in progress. Rechecking in 5 sec"
			sleep 5
		}
		if ($op.State -eq "failed")
		{
			$c='0'
			write-host "Switchback simulation has failed !!!!!" -foregroundcolor RED
			Logwrite "Switchback simulation has failed !!!!!"
			Mailer -subject "Switchback simulation has failed !!!!! Connect to system ASAP to check what happened"
			return $false
		}
	}
}

function PingServer ($servers)
{
	$someup = $false
	foreach ($server in $servers)
	{
		if (Test-Connection $server -Count 1 -ea 0 -Quiet)
		{ 
			LogWrite "pinging $server - up"
			$someup = $true
		} 
		else 
		{ 
			LogWrite "pinging $server - down"
			write-host "pinging $server - down"
			$someup = $false
			return $server
			break
			
		}
	}
	return $someup
}

function Check_MCC
{
	#This function will validate cluster vitals
	$MCState=Get-NcMetrocluster
	if ($MCState.LocalMode -eq "normal" -and $MCState.RemoteMode -eq "normal")
	{
		write-host "Metrocluster status looks normal - Check network between scripting machine to cluster LIF of failed cluster" -foregroundcolor YELLOW
		return $true
	}
	else 
	{
		write-host "Switchover has Occured !!! $($MCState.LocalClusterName) has switched over $($MCState.RemoteClusterName)" -foregroundcolor RED
		return $false
	}
}

function Check_Cluster_Peer
{
	$CPeer=Get-NcClusterPeer
	if ($CPeer.availability -ne "available")
	{
		Logwrite "Cluster Peering is $($CPeer.availability)"
		$PingStats=Ping-NcClusterPeer
		foreach ($PingStat in $PingStats)
		{
			if ($PingStat.PingStatus -ne "interface_reachable")
			{
				write-host "Some intercluster lif doesn't respond. Validate physical connectivity for intercluster network" -foregroundcolor RED
				Logwrite "Some intercluster lif doesn't respond. Validate physical connectivity for intercluster network"
				break
			}
			else
			{
				write-host "Link appears to be OK - Need to reinforce the cluster peering config ..." -foregroundcolor YELLOW
				Logwrite "Link appears to be OK - Need to reinforce the cluster peering config ..."
				
			}
		}
		#Reconfigure Cluster Peering
		Invoke-NcSsh "cluster peer modify -cluster $($CPeer.RemoteClusterName) -peer-addrs $($CPeer.PeerAddresses) -address-family ipv4"
	}
	else
	{
		write-host "Cluster peer is $($CPeer.availability)" -foregroundcolor Green
		Logwrite "Cluster Peering is $($CPeer.availability)"
	}
} 

function Check_BrokenDisk
{
    # Check for broken disks
    $Disks = Get-NcDisk 
	$BrokenDisks= $Disks | ?{ $_.DiskRaidInfo.ContainerType -eq "broken" }
    if ($BrokenDisks.length -gt 0) 
	{
		write-Host "The following disks are broken: " -ForegroundColor Red
		forEach ($BrokenDisk in $BrokenDisks) 
		{
			Write-Host $BrokenDisk.Name -ForegroundColor Red
			
		}
		return $BrokenDisks
	}
	else 
	{
	Write-Host "No broken disks were detected" -ForegroundColor Green
	}

    $MaintDisks= $Disks  | ?{ $_.DiskRaidInfo.ContainerType -eq "maintenance" }
    If ($MaintDisks.length -gt 0) 
	{
		Write-Host "The following disks are in maintenance: " -ForegroundColor Red
		forEach ($MaintDisk in $MaintDisks) 
		{
			Write-Host $MaintDisk.Name -ForegroundColor Red
        }
		return $MaintDisks
    } 
	else 
	{
		Write-Host "No maintenance disks were detected" -ForegroundColor Green
    }
    $PendDisks= $Disks  | ?{ $_.DiskRaidInfo.ContainerType -eq "pending" }
    If ($PendDisks.length -gt 0) 
	{
        Write-Host "The following disks are in pending: " -ForegroundColor Red
		forEach ($PendDisk in $PendDisks) 
		{
			Write-Host $PendDisk.Name -ForegroundColor Red
		}
		return $PendDisks
    } 
	else 
	{
		Write-Host "No pending disks were detected" -ForegroundColor Green
    }
}

function Check_DiskPool
{
 	#Validate that all disk are present
	$Disks = Get-NcDisk 
	$d0=$Disks | ?{$_.Pool -eq '0'}
	$d1=$Disks | ?{$_.Pool -eq '1'}
	if ($d0.count -eq "0" -or $d1.count -eq "0" )
	{
		write-host "    "
		write-host "There is a disk mismatch... Cluster cannot see all disks. Validate it before healing"
		Logwrite "There is a disk mismatch... Cluster cannot see all disks. Validate it before healing"
		return $false
	}
	else
	{
		write-host "    "
		write-host "Same number of drives in each pool. Proceeding with Healing" -foregroundcolor Green
		Logwrite "Same number of drives in each pool. Proceeding with Healing"
		return $true
	}
}

function MCC_AggrHealing 
{

	#Phase 1: Start aggregate healing
	$HAggrOp=Invoke-NcMetroclusterHeal -Aggregate -confirm:$False
	#Validate MCC operation
	if($HAggrOp)
	{
		$c='1'
		while ($c -eq '1')
		{
			$op=Get-NcMetroclusterOperation -operation "heal_aggregates" |?{$_.JobID -eq $HAggrOp.JobID}
			if ($op.State -eq "successful")
			{
				$c='0'
				write-host "Aggregate has been healed" -foregroundcolor Green
				Mailer -subject "Aggregate has been healed"
				Logwrite "Aggregate has been healed"
			}
			if ($op.State -eq "in_progress")
			{
				write-Host "Aggregate healing is still in processs" -foregroundcolor YELLOW
				Logwrite "Aggregate healing is still in processs"
				#Rechecking in 10 sec
				start-sleep 10
			}
			if ($op.State -eq "failed")
			{
				write-Host "ERROR: Aggregate healing failed" -foregroundcolor RED
				Logwrite "ERROR: Aggregate healing failed"
				Mailer -subject "ERROR: Aggregate healing failed"
				return $false
				break
			}
		}
	}
	else
	{
		$op=Get-NcMetroclusterOperation -operation "heal_aggregates" 
		write-host "Here is the status of Aggregate healing: $($op.State)"
		Logwrite "Here is the status of Aggregate healing: $($op.State)"
	}
	
}

function MCC_RootAggrHealing
{
	#Phase 2: Start Root-Aggregate healing
	$HRAggrOp=Invoke-NcMetroclusterHeal -RootAggregates -confirm:$False
	if($HRAggrOp)
	{
		$c='1'
		while ($c -eq '1')
		{
			$op=Get-NcMetroclusterOperation -operation "heal_root_aggregates" |?{$_.JobID -eq $HRAggrOp.JobID}
			if ($op.State -eq "successful")
			{
				$c='0'
				write-host "Root Aggregate has been healed" -foregroundcolor Green
				LogWrite "Root Aggregate has been healed"
				Mailer -subject "Root Aggregate has been healed"				
			}
			if ($op.State -eq "in_progress")
			{
				write-Host "Root Aggregate healing is still in processs" -foregroundcolor YELLOW
				Logwrite "Root Aggregate healing is still in processs"
				#Rechecking in 10 sec
				start-sleep 10
			}
			if ($op.State -eq "failed")
			{
				write-Host "ERROR: Root Aggregate healing failed" -foregroundcolor RED
				Logwrite "ERROR: Root Aggregate healing failed"
				Mailer -subject "ERROR: Root Aggregate healing failed"
				return $false
				break
			}
		}
	}
	else
	{
		$op=Get-NcMetroclusterOperation -operation "heal_root_aggregates"
		write-host "Here is the status of Root Aggregate healing: $($op.State)"
		LogWrite "Here is the status of Root Aggregate healing: $($op.State)"
	}
}

function Run-CMDtoSP ([string]$cmd)
{
    $Global:SSHStream.writeline($cmd)
	start-sleep 5
	$output=$Global:SSHStream.Read()
	return $output
}

function Mailer ([string]$Subject)
{
	$secpasswd = ConvertTo-SecureString "XXXXXXXX" -AsPlainText -Force
	$mycreds = New-Object System.Management.Automation.PSCredential ("XXXXXX@netapp.com", $secpasswd)
	Send-MailMessage -To $toEmail -Subject $Subject -BodyAsHtml $bodyEmail  -SmtpServer $mailServer -UseSSL -From $fromEmail -credential $mycreds
}


################
# MAIN
################

#Load Ontap Powershell Toolkits
If ( !(get-module -listavailable|Where-Object {$_.Name -eq "DataONTAP"})) 
{
	write-host `n"NetApp Powershell ToolKit is not installed !" `n
	Import-Module "C:\Program Files\NetApp\WFA\PoSH\Modules\DataONTAP"
}
#Variables
$Logfilebase = "c:\temp\switchback_log"
$maxlogfiles = 5
$maxlogfilesize = 2MB

$netappusername = 'admin'
$netapppasswordfile = 'na_pwd_do_not_delete'

$SPpasswordfile = 'SP_pwd_do_not_delete'
$passwordfile = "$($PSScriptRoot)\$($SPpasswordfile)"
$SPusername="admin"

$FailedCluster=$null

$fromEmail="ASB@netapp.com"
$toEmail="david.benadiba@netapp.com"
$bodyEmail="Automatic Switchback script"
$mailServer="smtp.office365.com" 

$clusters=$clusterA,$clusterB
$SPs=$SPA,$SPB

write-host "This script will validate that MCC is not in switchover"
write-host "It will run a switchback after checking MCC vitals"
write-host "    "
Logwrite "##############################################################."
Logwrite "Starting checking..."
if ($ValidateEntries)
{
	Logwrite "Validating Entries... "
	$Entries=$clusterA,$clusterB,$SPA,$SPB
	$Validations = New-Object System.Collections.ArrayList
	foreach ($Entry in $Entries)
	{
		$State=PingServer -servers $Entry
		$Validations.Add($State) | out-null;
	}
	$InvalidEntry=$Validations|?{$_ -ne $true}
	if ($InvalidEntry)
	{
		Write-host "$($InvalidEntry.count) Non-Pingable host has been entered as parameters: $($InvalidEntry)" -foregroundcolor RED
	}
	else
	{
		Write-host "All provided entries answer to ping requests" -foregroundcolor Green
		Logwrite "Accessing Clusters using Powershell API"
		foreach ($cluster in $clusters)
		{
			$connection=Connect_Filer $cluster
			if ($connection -eq $false)
			{
				Write-host "Cannot connect to cluster $($cluster)" -foregroundcolor RED
			}
			else
			{
				Write-host "Succesfully connected to $($cluster) using password in $($netapppasswordfile)" -foregroundcolor Green
			}
		}
		Import-PoshModule
		foreach ($SP in $SPs)
		{
			$connection=Connect_SP $SP
			if ($connection -eq $false)
			{
				Write-host "Cannot connect to SP $($SP)" -foregroundcolor RED
			}
			else
			{
				Write-host "Succesfully connected to $($SP) using password in $($SPpasswordfile)" -foregroundcolor Green
				Close-SSHSession
			}
		}
	}
}
else
{
	write-Host "Pinging Clusters"
	Logwrite "Pinging Clusters "
	foreach ($cluster in $clusters)
	{
		$state=PingServer -servers $cluster
		if ($state -ne $true)
		{
			break
		}
	}
	if ($state -ne $true)
	{
		$FailedCluster=$state
	}
	if ($FailedCluster)
	{
		write-host "    "
		write-host "Switchover may have occured" -foregroundcolor YELLOW
		Logwrite "Switchover may have occured"
		write-host "Validating metrocluster using alive cluster..."
		#Who is the alive node?
		$AliveCluster=$clusters |?{$_ -ne $FailedCluster}
		write-host "Alive cluster is: $($AliveCluster) Trying to connect..."
		Logwrite " Alive cluster is: $($AliveCluster) Trying to connect... "
		write-host "    "
		Connect_Filer $AliveCluster
		$FailedCluster_state=Check_MCC
		if ($FailedCluster_state -eq $false)
		{
			Mailer -subject "Switchover has occured. Script will try to run automatic giveback after checks"
			write-host "Starting Checking before Healing"
			#Check broken disks
			write-host "     "
			write-host "Disk Checks"
			$BadDisk=Check_BrokenDisk
			if ($BadDisk)
			{
				write-host "There is broken disk, Replace them before switchback" -foregroundcolor Red
				Mailer -subject "System found bad disk, Please replace before running switchback"
				Logwrite "There is broken disk, Replace them before switchback"
				Logwrite "$($BadDisk)"
			}
			else
			{
				$DPool=Check_DiskPool
				if ($DPool -eq $false)
				{
					write-host "Disk pool mismatch detected"
				}
				else
				{
					#Start metro healing
					LogWrite "Starting Aggrgegate Healing ..."
					write-host "Starting Aggregate healing"
					MCC_AggrHealing
					write-host "    "
					write-host "Starting Root Aggregate healing  "
					MCC_RootAggrHealing
					Import-PoshModule
					
					#Linking SP with cluster IP
					$CplA=$clusterA,$SPA
					$CplB=$clusterB,$SPB
					
					#Searching ip of the failed node
					$cpl=$CplA,$CplB
					foreach($cp in $cpl )
					{
						$valid=$cp |?{$_ -match $FailedCluster}
						if($valid)
						{
							write-host "SP of the failed node is: $($cp[1])"
							$SPFailedNode=$cp[1]
							Logwrite "SP of the failed node is: $($cp[1])"
						}
						
					}
					if (!$HumanInteraction)
					{
						Logwrite "Connecting to SP to run boot_ontap command"
						Connect_SP $SPFailedNode 
						$Global:SSHStream.writeline("y") #trick in case SP is already connected
						sleep 2
						Run-CMDtoSP -cmd "help"
						Run-CMDtoSP -cmd "system console"
						Run-CMDtoSP -cmd "boot_ontap"
						Close-SSHSession
					}
					else
					{
						write-host "#############################"
						write-host "#############################"
						write-host "Variable Human interaction is on"
						write-host "It is now time to connect to the failed node SP and start it"
						write-host "Please connect to : $($SPFailedNode) using Putty or any other SSH terminal "
						write-host "Once connected run the following command : system console"
						write-host "Prompt should look like: LOADERX>"
						write-host "Now start the system running the following command: boot_ontap"
						write-host "When cluster has booted exit SSH console and return to the Powershell script"
						write-host "#############################"
						write-host "#############################"
						
						Logwrite "Requesting User to boot the system using SP:  $($SPFailedNode)"
						$Answer = read-host -Prompt `n" Did you start the Failed cluster using above lines? (yes/no)"
						Logwrite "Operator answer : $Answer"
						if ($Answer -eq "yes" -or $Answer -eq "y")
						{
							write-host "Continuing with switchback"
						}
					}
					write-host "   "
					write-host "Waiting for cluster to start..."
					Logwrite "Pinging Failed cluster after boot (it may take a while) ..."
					$cou='1'
					while ($cou -eq '1')
					{
						#ping cluster lif
						$DeadOrAlive=PingServer ($FailedCluster)
						if ($DeadOrAlive -eq $true)
						{
							write-host "Cluster is up -- Let's proceed with the switchback"
							Logwrite "Cluster is up -- Continuing with switchback"
							$cou='2'
						}
						start-sleep 5
					}
					#After Node will be up and running
					start-sleep 20 # sleep 20s to make cluster healthier
					write-host "     "
					write-host "Checking cluster Peer..."
					LogWrite "Checking Cluster peer before running SB"
					Check_Cluster_Peer
					
					#check that failed node is waiting for giveback
					switchback
				}
			}
		}
	}
	else
	{
		write-host "Everything is under control"
	}

}

