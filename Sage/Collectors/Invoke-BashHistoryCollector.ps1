# Collectors/Invoke-BashHistoryCollector.ps1
# Runs ON the remote Linux VM. Returns structured bash history and cmd.log data.
# All output is plain hashtables/strings — safe for CLIXML deserialization.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables',
    Justification = 'Variables consumed for ExamStart/ExamEnd filtering and password for sudo.')]
param(
    [Parameter()][hashtable] $Variables = @{}
)

$Result = @{
    Available = $false
    Reason    = $null
    Data      = @{
        BashHistory = @()
        CmdLog      = @()
    }
    Errors    = @()
}

# ── Determine exam time window from Variables ─────────────────────────────────
$ExamStart = if ($Variables.ExamStart) {
    [datetime]$Variables.ExamStart
}
else {
    [datetime]::MinValue
}

$ExamEnd = if ($Variables.ExamEnd) {
    [datetime]$Variables.ExamEnd
}
else {
    [datetime]::MaxValue
}

$UserName = if ($Variables.UserName) { $Variables.UserName } else { 'student' }
$Password = if ($Variables.Password) { $Variables.Password } else { $null }
$CmdLogPath = if ($Variables.CmdLogPath) { $Variables.CmdLogPath } else { '/var/log/cmd.log' }

$Result.Available = $true

# ── Collect bash history ──────────────────────────────────────────────────────
try {
    $HistoryPath = "/home/$UserName/.bash_history"
    if (Test-Path $HistoryPath) {
        $RawHistory = Get-Content $HistoryPath -ErrorAction Stop
        $ParsedEntries = @()

        for ($I = 0; $I -lt $RawHistory.Count; $I++) {
            if ($RawHistory[$I] -match '^#((\d{10})+)$') {
                $EpochTime = $Matches[1]
                $Timestamp = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$EpochTime).LocalDateTime

                if ($Timestamp -ge $ExamStart -and $Timestamp -le $ExamEnd -and ($I + 1) -lt $RawHistory.Count) {
                    $ParsedEntries += @{
                        Timestamp = $Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
                        Command   = $RawHistory[$I + 1]
                    }
                }
                # Always skip the command line following an epoch timestamp
                $I++
            }
            elseif ($RawHistory[$I] -ne '') {
                $ParsedEntries += @{
                    Timestamp = $null
                    Command   = $RawHistory[$I]
                }
            }
        }

        $Result.Data.BashHistory = $ParsedEntries
    }
    else {
        $Result.Errors += "Bash history file not found: $HistoryPath"
    }
}
catch {
    $Result.Errors += "Bash history collection failed: $($_.Exception.Message)"
}

# ── Collect cmd.log ───────────────────────────────────────────────────────────
try {
    $CmdLogContent = $null
    if ($Password) {
        $CmdLogContent = Write-Output $Password | sudo -S cat $CmdLogPath 2>/dev/null
    }
    elseif (Test-Path $CmdLogPath -ErrorAction SilentlyContinue) {
        $CmdLogContent = Get-Content $CmdLogPath -ErrorAction Stop
    }

    if ($CmdLogContent) {
        $CmdLogHeaders = 'TimestampSession,RemoteHost,User,Pwd,Command'
        $CsvText = $CmdLogHeaders + "`n" + ($CmdLogContent -join "`n")
        $CmdLogEntries = $CsvText | ConvertFrom-Csv

        $ParsedCmdLog = @()
        foreach ($Entry in $CmdLogEntries) {
            $ParsedDate = $null

            if ($Entry.TimestampSession -match '^(\w{3})\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2})') {
                $Month = $Matches[1]
                $Day = $Matches[2].PadLeft(2, '0')
                $Time = $Matches[3]
                $Year = (Get-Date).Year
                $DateString = "$Month $Day $Year $Time"
                try {
                    $ParsedDate = [DateTime]::ParseExact(
                        $DateString,
                        'MMM dd yyyy HH:mm:ss',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                }
                catch {
                    $ParsedDate = $null
                }
            }

            $RemoteHost = $Entry.RemoteHost
            $User = $Entry.User
            $WorkDir = $Entry.Pwd
            $Command = $Entry.Command

            foreach ($FieldName in @('RemoteHost', 'User', 'WorkDir', 'Command')) {
                $FieldVal = (Get-Variable -Name $FieldName -ValueOnly)
                if ($FieldVal -like '*=*') {
                    Set-Variable -Name $FieldName -Value (($FieldVal -split '=')[-1].Trim())
                }
            }

            $InWindow = $true
            if ($ParsedDate -and $ExamStart -ne [datetime]::MinValue) {
                $InWindow = ($ParsedDate -ge $ExamStart -and $ParsedDate -le $ExamEnd)
            }

            if ($InWindow) {
                $ParsedCmdLog += @{
                    Timestamp  = if ($ParsedDate) { $ParsedDate.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                    RemoteHost = $RemoteHost
                    User       = $User
                    Pwd        = $WorkDir
                    Command    = $Command
                }
            }
        }

        $Result.Data.CmdLog = $ParsedCmdLog
    }
    else {
        $Result.Errors += "cmd.log not accessible or empty: $CmdLogPath"
    }
}
catch {
    $Result.Errors += "cmd.log collection failed: $($_.Exception.Message)"
}

return $Result
