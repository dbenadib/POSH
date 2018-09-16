Param(
  [Parameter(Mandatory=$True)]
   [string]$LogsPath,
  [Parameter(Mandatory=$False)]
   [switch]$DisplayError,
  [Parameter(Mandatory=$False)]
   [string]$OutputErrorFile)
   
#Clear-Host
$ErrorActionPreference = "Continue"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"
if (!$OutputErrorFile)
{	
	$OutputErrorFile ="C:\Temp\Robocopy_errors_logs.log"
	write-host "You didn't provide Output File path so by default it will logged on: $($OutputErrorFile)" -foregroundcolor YELLOW
}


function Tail-RobocoLog([string]$LogPath,[string]$OutputErrorFile)
{
	#$cLog = "C:\Users\dbenadib\Desktop\test.log"

	## Use Regular Expression to grab the following Table
	#               Total    Copied   Skipped  Mismatch    FAILED    Extras
	#    Dirs :         1         0         1         0         0         0
	#   Files :         1         0         1         0         0         0
	
	$robo_test = gc $LogPath
	$robo_results = $robo_test -match '^(?= *?\b(Total|Dirs|Files)\b)((?!    Files).)*$'
	if ($DisplayError)
	{
		$err=$Null
		$err=$robo_test -match 'ERROR'
		write "+++++++++++++++++++++" | Out-File -filepath $OutputErrorFile -Append -Encoding ASCII
		write $LogPath | Out-File -filepath $OutputErrorFile -Append -Encoding ASCII
		$err | Out-File -filepath $OutputErrorFile -Append -Encoding ASCII
	}

	## Convert Table above into an array
	$robo_arr = @()
	foreach ($line in $robo_results){
		$robo_arr += $line
	}

	## Create Powershell object to tally Robocopy results
	$row=$Null
	$row = "" |select COPIED, MISMATCH, FAILED, EXTRAS, errors
	$row.COPIED = [int](($robo_arr[1] -split "\s+")[4]) + [int](($robo_arr[2] -split "\s+")[4])
	$row.MISMATCH = [int](($robo_arr[1] -split "\s+")[6]) + [int](($robo_arr[2] -split "\s+")[6])
	$row.FAILED = [int](($robo_arr[1] -split "\s+")[7]) + [int](($robo_arr[2] -split "\s+")[7])
	$row.EXTRAS = [int](($robo_arr[1] -split "\s+")[8]) + [int](($robo_arr[2] -split "\s+")[8])
	$row.errors = $err
	return $row
}

#Main

#Get All Log in $LogsPath

$Logs=Get-ChildItem -path $LogsPath"\*.log"

foreach ($Log in $Logs)
{
	$Status=$Null
	$Status=Tail-RobocoLog -LogPath $Log -OutputErrorFile $OutputErrorFile
	write-host =======================================
	if($Status.failed -eq '0')
	{
		write-host	$Log.FullName -foregroundcolor Green
	}
	else
	{
		write-host	$Log.FullName -foregroundcolor Red
	}
	write-host "                                 "
	write-host "COPIED Items: "$Status.copied "FAILED Items: " $Status.failed "MISMATCH Items: " $Status.MISMATCH "Extra Items: " $Status.EXTRAS
	write-host "                                 "
	if ($DisplayError)
	{
		$Status.errors
	}
	write-host =======================================
	
}




