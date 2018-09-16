# Parameter help description
Param(
	[Parameter(Mandatory=$true)][string[]]$Cluster) 
###Variables
$netappusername = 'admin'
$netapppasswordfile = 'na_pwd_do_not_delete'
# Current Date in "MM-DD-YY" format 
$TodayDate = get-date -uformat "%m-%d-%Y"
#Report retention in days
$RetentionReports=30
$REPORTdate = (get-date).AddDays(-1).ToString("MM-dd-yyyy")
#Mail Variables
$SMTPserver = "XXX.XXX.XXX.XXX"
$SMTPrecipient = @("a@netapp.com","b@netapp.com","c@netapp.com")
[string[]] $MAILsubject = "Onatp Snapmirror / Snapvault Report"
# Output Files
$ReportsChecksDir="C:\temp\SnapmirrorReports\"
# Output Tables
$STATUStable = New-Object system.Data.DataTable "SME Backup Status"

## To create New Columns For the Reports
$STATUSitems = ("SourcePath","DestinationPath","Healthy","Type","State","LagTime","Schedule","Alert","System_Manager_Link")

####Functions

function Connect_Filer([string]$filernameSRC)
{
	#validate password file exists and convert to PS-Cred object
	$passwordfile = "$($PSScriptRoot)\$($netapppasswordfile)"
	if (!(Test-Path $passwordfile)) 
	{
			Write-host "Encrypting NetApp Creds"
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

## Function for creating report tables
function SendMailHTML($Subject,$file)
{
      $SMTPclient = new-object system.net.mail.smtpClient
      $MAILMessage = New-Object system.net.mail.mailmessage
      $attachement = new-object system.net.mail.attachment($file)
      
   
      $SMTPclient.Host = $SMTPServer
      $MAILmessage.from = "script@netapp.com"
      $SMTPrecipient | foreach {$MAILmessage.To.Add($_)} 
      $MAILmessage.Subject = $Subject
      $MAILmessage.IsBodyHTML = 1
      $MAILmessage.body = get-content $HTMLoutput
      
      if ( ($file -ne $null) -and ((get-childitem $file) -ne $null) -and ((get-childitem $file).length -ne 0) ){ 
             
            
            $Mailmessage.Attachments.Add($attachement)
      }
      $SMTPclient.Send($MAILmessage)
      
}

function CreateTable($HEADERSTable)
   {
        $BACKUPStable = New-Object system.Data.DataTable  
        $NBcol=[int]0
    
        foreach ($i in $HEADERStable)
        { 
            $NBcol++
            $j = $i -replace " ",""

            $column = New-Object system.Data.DataColumn $j,([string])
            $BACKUPStable.columns.add($column)            
         }
        Set-Variable -Value $NBcol -Name NBcol -scope script
        return ,$BACKUPStable
}

## CSS styles of the HTML page 

function HTMLcreateheader()
{
   $HTMLheader = @" 
   <head>
    <style> 
    .body {font-family : Arial; font-size: 10pt}
    
    table.Title {border: Solid 1px #A6A6A6; background-color: #EBF3FF;width: 100%; padding : 10px 10px 10px 10px}
    table.Title tr td {border: none; font-size: 20pt; color: Black; font-family : Arial; text-align: center}
  
    table.Title_1 {border-left: Solid 3px #0067C5; border-bottom: Solid 3px #0067C5; color: #0067C5; font-family : Arial; font-size: 14pt; font-weight: Bold; font-style : Italic; padding: 2px 30px 2px 5px}

    table.ReportTable {border: Solid 1px #A6A6A6; text-align:center} 
    table.ReportTable thead tr td.MergedContent {background-color: #0067C5; color: white; font-weight: Bold; font-family : Arial; font-size: 12pt; text-align:left; padding : 2px 10px 2px 10px}
    table.ReportTable thead tr th {border: Solid 1px #A6A6A6;background-color: #0074DE; color: white; font-weight: Bold; font-family : Arial; font-size: 11pt; padding : 2px 3px 2px 3px}     
 	
    table.ReportTable tbody tr td {border: Solid 1px #A6A6A6; background-color:#EBF3FF;font-family : Arial; font-size: 9.5pt; padding : 2px 6px 2px 6px}      
	table.ReportTable tbody tr td.successfull {background-color: #C6EFCE; color: #006100; font-weight: Bold; font-family : Arial; font-size: 10pt}
    table.ReportTable tbody tr td.warning {background-color: #FFEB9C; color: #9C6500;  font-weight: Bold; font-family : Arial; font-size: 10pt} 
    table.ReportTable tbody tr td.error {background-color: #FFC7CE; color: #9C0006; font-weight: Bold; font-family : Arial; font-size: 10pt}
    table.ReportTable tbody tr td.WhiteContent {color: #FFFFFF; border: Solid 1px #A6A6A6;font-family : Arial; font-size: 10pt}     
    </style>
    </head>
"@
    AddContentToHTML $HTMLoutput $HTMLheader  
    $HTMLtitle = "<table class='Title'><tr><td>VisaCal : Snapmirror / Snapvault Report for cluster $($Cluster) <br/><span style='font-size: 18pt'>Report Date : " + ${REPORTdate} + "</span></td></tr></table><br/>"    
    AddContentToHTML $HTMLoutput $HTMLtitle
}

## To transform PS HTLM Table in good format

function HTMLaddtable($HTMLtemp,$NBcol,$HTMLoutput,$html_table)
{
        $html_table = $html_table -replace "<table>",$HTMLtemp
        $html_table = $html_table -replace "NBcol",$NBcol
        $html_table = $html_table -replace "</th></tr>","</th></tr></thead><tbody>"
        #$html_table = $html_table -replace  "Server Name : hostname </td></tr>","Server Name : ${SERVERname} </td></tr>"
        $html_table = $html_table -replace "<td></td>","<td class='WhiteContent'>.</td>"
        $html_table = $html_table -replace "<td>True","<td class='successfull'>True"
        $html_table = $html_table -replace "<td>False","<td class='error'>False"
        $html_table = $html_table -replace "<td>Alert","<td class='error'>Alert"
        $html_table = $html_table -replace "<td>OK","<td class='successfull'>OK"
        $html_table = $html_table -replace ".000000</td>","</td>"
        $html_table = $html_table -replace "<td>Warninghour","<td class='warning'>"
        $html_table = $html_table -replace "<td>Warning","<td class='warning'>Warning"
        $html_table = $html_table -replace "<td>Error","<td class='error'>Error"
        $html_table = $html_table -replace "<td>Critical","<td class='error'>Critical"

        $html_table = $html_table -replace "&lt;","<"
        $html_table = $html_table -replace "</a&gt;","</a>";
        $html_table = $html_table -replace "&quot;","`"";
        $html_table = $html_table -replace "&gt;",">";
        
        $html_table = $html_table -replace "</table>","</tbody></table><br/>"
        
    	AddContentToHTML $HTMLoutput  $html_table 
        AddContentToHTML $HTMLoutput '<b><b/>'
}

## Remove old reports
function ReportFolderAdministration()
{  
   
    Get-ChildItem $WorkDir -Recurse -Include "SnapmirrorReport_HTML_*.htm" | WHERE {($_.CreationTime -le $(Get-Date).AddDays(-$RetentionReports))} | Remove-Item -Force
}

## Add Line to an HTML file

function AddContentToHTML($HTMLFile,$ContentToAdd)
{
    Add-Content -path $HTMLFile -value $ContentToAdd
}

#Rotate logs
function RotateReport()
{
 #Remove old reports
 Get-ChildItem -literalpath $ReportsChecksDir -Recurse| WHERE {($_.CreationTime -le $(Get-Date).AddDays(-$RetentionReports))} | Remove-Item -Force
 $files=Get-ChildItem -literalpath $ReportsChecksDir -Recurse 
 foreach ($file in $files)
 {
	if($file.name -eq "SnapmirrorReport_HTML.htm")
	{
		rename-item -path $ReportsChecksDir\SnapmirrorReport_HTML.htm -newname "SnapmirrorReport_HTML_$REPORTdate.htm"
	}
 }
}

function Get-UnixDate ($UnixDate) {
    [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($UnixDate))
 }
 

function CreateSMEreport($Server)
{
    # Call function to create a table to store data
    $STATUStable = createtable $STATUSitems
   
    # 
        AddContentToHTML $HTMLoutput "<table class='Title_1'><tr><td> Snapmirror Status Report </td></tr></table><br/>"

                    $STATUStable.Clear()
                    #$SMEbackups = 0

                    #$Rels=get-ncsnapmirror |?{$_.IsHealthy -eq $false}
                    $SM=get-ncsnapmirror 
                    $Rels=$SM|?{$_.Policy -eq "DPDefault"  }
                   	foreach ($Rel in $Rels)
					{
                        #$STATUSitems = ("SourcePath","Destination-Path","Healthy","State","LagTime","Schedule")
                                           
                        $row = $STATUStable.NewRow()
                        $row.SourcePath=$Rel.SourceLocation
                        $row.DestinationPath=$rel.DestinationLocation
                        $row.Healthy=$rel.IsHealthy
                        if($rel.IsHealthy -eq $False)
                        {
                            $row.System_Manager_Link='<a href="https://'+$Cluster+'">System Manager</a>'
                        }
                        if($rel.IsHealthy -eq $true)
                        {
                            $row.System_Manager_Link="N/A"
                        }
                        $row.schedule=$rel.schedule
                        $lastTransferTime = Get-UnixDate -UnixDate $rel.LastTransferEndTimestamp
                        $lagTime = New-TimeSpan -Start $lastTransferTime -End (Get-Date)
                        $row.LagTime=[timespan]::fromseconds($rel.LagTime).tostring()
                        $row.State = $Rel.MirrorState
                        $row.type=$rel.PolicyType
                        $STATUStable.Rows.Add($row)
                                             
                     }					
					  
					  $html_table = ($STATUStable| Select * -exclude RowError,RowState,Table,ItemArray,HasErrors| ConvertTo-Html -fragment|Where{$_ -notmatch "<col" -and $_ -notmatch "</col"})
                      $HTMLtemp = @"
                      <table class='ReportTable' cellspacing='0px' cellpadding='0px'> 
                      <thead><tr><td colspan='NBcol' class='MergedContent'>Snapmirror </td></tr>
"@
                        HTMLaddtable $HTMLtemp $NBcol $HTMLoutput $html_table 
                        
                        $STATUStable2 = createtable $STATUSitems
                        AddContentToHTML $HTMLoutput "<table class='Title_1'><tr><td> Snapvault Status Report </td></tr></table><br/>"
                        $STATUStable2.Clear()
                        $SVaults=$SM |?{$_.Policy -ne "DPDefault"  }
                        foreach ($SVault in $SVaults)
                         {
                         #$STATUSitems = ("SourcePath","Destination-Path","Healthy","State","LagTime","Schedule")
                                                             
                            $row = $STATUStable2.NewRow()
                            $row.SourcePath=$SVault.SourceLocation
                            $row.DestinationPath=$SVault.DestinationLocation
                            $row.Healthy=$SVault.IsHealthy
                            $lagTime = New-TimeSpan -Start $lastTransferTime -End (Get-Date)
                            $LagTime=[timespan]::fromseconds($SVault.LagTime)
                            $row.LagTime=$LagTime.tostring()
                            if($Lagtime.days -ge '1')
                            {
                                $row.Alert = "Alert"
                            }
                            else 
                            {
                                $row.Alert = "Less than 1 days"   
                            }
                            if($SVault.IsHealthy -eq $true -and $row.Alert -eq "Alert")
                            {
                                $row.System_Manager_Link='<a href="https://'+$Cluster+'">System Manager</a>'
                            }
                            if($SVault.IsHealthy -eq $False)
                            {
                                $row.System_Manager_Link='<a href="https://'+$Cluster+'">System Manager</a>'
                            }
                            if($SVault.IsHealthy -eq $true -and $row.Alert -ne "Alert" )
                            {
                                $row.System_Manager_Link="N/A"
                            }
                            $row.schedule=$SVault.schedule
                            $lastTransferTime = Get-UnixDate -UnixDate $SVault.LastTransferEndTimestamp
                            
                            $row.State = $Svault.MirrorState
                            $row.type=$SVault.PolicyType
                            $STATUStable2.Rows.Add($row)        
                        }					
                        $html_table =($STATUStable2| Select * -exclude RowError,RowState,Table,ItemArray,HasErrors| ConvertTo-Html -fragment|Where{$_ -notmatch "<col" -and $_ -notmatch "</col"})
                        $HTMLtemp = @"
                        <table class='ReportTable' cellspacing='0px' cellpadding='0px'> 
                        <thead><tr><td colspan='NBcol' class='MergedContent'>Snapvault </td></tr>
"@
                                          HTMLaddtable $HTMLtemp $NBcol $HTMLoutput $html_table 
                                          
                                         
                                  
                                          if ($HTMLerror) 
                                          {
                                              $HTMLtext =   '<span style="font-family:Arial; font-size:13px; font-weight:bold; color:#9C0006"'+">  Please check the following report(s) on $SMEserver :<br/>" 
                                              Add-content -path $HTMLoutput -value $HTMLtext
                                              Add-content -path $HTMLoutput -value $HTMLerror
                                              Add-content -path $HTMLoutput -value "</span><br/><br/>"
                                          }

					
   
}#End Function

# Call function to create the Header of HTML Page (head+Style)
RotateReport
Connect_Filer -filernameSRC $Cluster
$HTMLoutput = New-Item -name "SnapmirrorReport_HTML.htm" -ItemType file -Path $ReportsChecksDir -force
HTMLcreateheader
CreateSMEreport

#SendMailHTML $MAILsubject $HTMLoutput

