# Veeam Report

$TranscriptFile = "\\networkshare\Powershell\PSLogs\VeeamReport_$(get-date -f MMddyyyyHHmmss).txt"
$start_time = Get-Date
Start-Transcript -Path $TranscriptFile

Add-PSSnapin VeeamPSSnapIn

############ CREDENTIALS ##############

# Get passwords
$backup_server= "veeam1"
$user = "someuser"

$user_pwd = "gobbledygook" | ConvertTo-SecureString

# Create credential objects
$user_creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$user_pwd -ErrorAction Stop

############ BACKUP ANALYSIS ##############
# Connect to Veeam
Write-Output "Connecting to Veeam..."
Connect-VBRServer -Credential $user_creds -Server $backup_server

$start_date = (Get-Date).AddHours(-24)

$veeam_jobs = Get-VBRJob 
Write-Host $veeam_jobs

$all_jobs = New-Object System.Collections.ArrayList


$veeam_jobs | ForEach-Object { 
    $job = $_
    $job_name = $_.Name
    Write-Host "Job: $job_name"
    $backup_session = $job.FindLastSession()
    $backup_session | Foreach-Object { 
        Write-Host ("Backup session: " + $_.Name)
        $task_sessions =  Get-VBRTaskSession -Session $_
        $task_sessions | ForEach-Object {
            Write-Host ("Task session: " + $_.Name)
            $job_list = New-Object -TypeName PSObject
            $session_hash = @{}
            $session_hash["details"] = ($_.Logger.GetLog().UpdatedRecords | Where {$_.Status -notmatch "ESucceeded" } | Select -ExpandProperty title)
            $session_hash["status"] = ($_ | Select -ExpandProperty status)
            $session_hash["starttime"] = ($_ | Select -ExpandProperty Progress | Select -ExpandProperty StartTimeLocal)
            $session_hash["endtime"] = ($_ | Select -ExpandProperty Progress | Select -ExpandProperty StopTimeLocal)
            $session_hash["name"] = ($_ | Select -ExpandProperty name)
            $job_list = New-Object -TypeName PSObject -Property $session_hash
            $all_jobs.Add($job_list) | Out-Null
        }
    }
}
Disconnect-VBRServer

# Generate email report
$email_list=@("email1@example.com")
$subject = "Veeam VM Report"
$body = @()
$user = $env:USERNAME
$body += "Veeam Backup Report called by $user.`n`n"

$table_body = "<table border=`"3`"><thead><tr><th>Server Name</th><th>Status</th><th>Start Time</th><th>End Time</th><th>Details</th></tr></thead><tbody>"

$failed=0
$warning=0
$success=0
$pending=0

$all_jobs | Sort-Object -Property @{Expression = "status"; Descending=$true},@{Expression = "name"; Descending=$false} | ForEach-Object {
   if  ($_.status -match "FAILED|ERROR") {
        $bgcolor = "red"
        $failed++
    }
    elseif ($_.status -match "WARNING") {
        $bgcolor = "yellow"
        $warning++
    }
    elseif ($_.status -match "SUCCESS") {
        $bgcolor = "green"
        $success++
    }
    else {
        $bgcolor = "white"
        $pending++
    }

    $table_body += ("<tr bgcolor=`"" + $bgcolor +"`"><td>" + $_.name + "</td><td>" + $_.status + "</td><td>"  + $_.starttime +"</td><td>" + $_.endtime + "</td><td>"  + $_.details + "</td></tr>")
}
$table_body += "</tbody></table>"
$body += "<b>Total successful:</b> $success<br><b>Total warning:</b> $warning<br><b>Total failed:</b> $failed<br><b>Total pending:</b> $pending<br><br>"
$body += $table_body

Stop-Transcript

$MailMessage = @{
    To = $email_list
    From = "Veeam Report<Donotreply@example.com>"
    Subject = $subject
    Body = ($body -join "<br/>")
    SmtpServer = "smtp.example.com"
    ErrorAction = "Stop"
}
Send-MailMessage @MailMessage -BodyAsHtml

