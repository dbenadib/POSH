# Author  : David BENADIBA
# Title   : ExecTime_log_parser.ps1
# Version : v0.1
# Exemple : .\ExecTime_log_parser.ps1 -LogPath C:\Temp\Subcontractor\Subcontractor
Param(
                [Parameter(Mandatory=$true)][string]$LogPath    
)

$files=Get-ChildItem -File -path $Logpath  |?{$_.name -like "*txt"}
#Create a CSV File for Report
$Report=$LogPath+"\robocopy-$(get-date -format "dd-MM-yyyy_HH-mm-ss").csv"
write-host "$($Report)"
write "FileName;SourcePath;DestinationPath;StartedDate;End Date;Elapsed Time" | out-file -filepath $Report
foreach ($file in $files)
{
                Write-host "-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"
                Write-host "Parsing file $($file)" -foregroundcolor Green
                $Output=@{}
                $Content=get-content $file.FullName | ?{$_ -match 'Started :|Ended : | Source : | Dest :'}|%{$_ -replace '',''}
                #Parsing $Content
                foreach ($C in $Content)
                {
                                if ($C -match "Started : ")
                                {
                                                #Found Started Date
                                                #$d=$C.Replace("Started : ","")
                                                $d=$C -split "\s+"
                                                #build Date
                                                $date=$d[3]+" "+$d[4]+" "+$d[5]+" "+$d[6]+" "+$d[7]+" "+$d[8]
                                                $StartedDate=[DateTime]$date
                                                $Output.StartedDate=$date
                                                #write-host "Started Date equal $($StartedDate)"
                                }
                                if ($C -match "Ended : ")
                                {
                                                #Found Ended Date
                                                #$d=$C.Replace("Ended : ","")
                                                #$EndedDate=[DateTime]$d
                                                #$Output.EndDate=$d

                                                $d=$C -split "\s+"
                                                #build Date
                                                $date=$d[3]+" "+$d[4]+" "+$d[5]+" "+$d[6]+" "+$d[7]+" "+$d[8]
                                                $EndedDate=[DateTime]$date
                                                $Output.EndDate=$date

                                                #write-host "Ending Date equal $($EndedDate)"
                                }
                                if ($C -match "Source : ")
                                {
                                                $SourcePath=$C.Replace("Source : ","")
                                                #$SourcePath
                                                $Output.SourcePath=$SourcePath
                                }
                                if ($C -match "Dest : ")
                                {
                                                $DestPath=$C.Replace("Dest : ","")
                                                #$DestPath
                                                $Output.DestPath=$DestPath
                                }
                                
                }
                #Calculate Elapsed Time:
                $Elapsed=$EndedDate-$StartedDate
                [String]$HumanElapsedTime="$($Elapsed.days) d - $($Elapsed.hours) h - $($Elapsed.minutes) m "
                $Output.Elapsed= $HumanElapsedTime
                $Output.LogFile= $file.name
                write "$($Output.LogFile);$($Output.SourcePath);$($Output.DestPath);$($Output.StartedDate);$($Output.EndDate);$($Output.Elapsed)" | out-file -filepath $Report -Append
                
                                
}
