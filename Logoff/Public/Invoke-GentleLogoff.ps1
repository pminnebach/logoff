#Requires -Version 5.1
#Requires -RunAsAdministrator
function Invoke-GentleLogoff {
    <#
    .SYNOPSIS
        Enumerates interactive sessions on the local Windows server and performs a gentle logoff.

    .DESCRIPTION
        Intended to run from Task Scheduler before a scheduled reboot. Sends timed warning
        messages to each logged-on user, waits through a grace period, then requests a
        graceful logoff (WM_ENDSESSION) for each remaining interactive session.

        Skips session 0 and non-interactive session states (Listen, Init, etc.).

    .PARAMETER GracePeriodMinutes
        Total time to wait after the first warning before logging users off.

    .PARAMETER WarningMinutes
        Minutes before logoff at which to send each warning. Values are relative to logoff time
        (e.g. 15, 5, 1 sends warnings at T-15, T-5, and T-1 minutes).

    .PARAMETER Message
        Custom reboot warning text shown to users.

    .PARAMETER ExcludeUsers
        SAM account names to skip (case-insensitive), e.g. 'Administrator'.

    .PARAMETER LogPath
        Optional file path for operational logging.

    .OUTPUTS
        System.Boolean
        Returns $true when all interactive users are logged off; otherwise $false.

    .EXAMPLE
        Invoke-GentleLogoff -GracePeriodMinutes 15 -WarningMinutes 15,5,1

    .EXAMPLE
        Invoke-GentleLogoff -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidateRange(1, 120)]
        [int] $GracePeriodMinutes = 15,

        [Parameter()]
        [int[]] $WarningMinutes = @(15, 5, 1),

        [Parameter()]
        [string] $Message = 'This server is scheduled to reboot soon. Please save your work and log off.',

        [Parameter()]
        [string[]] $ExcludeUsers = @(),

        [Parameter()]
        [string] $LogPath
    )

    Initialize-WtsNative

    $WarningMinutes = @($WarningMinutes | Sort-Object -Descending -Unique)
    $maxWarning = ($WarningMinutes | Measure-Object -Maximum).Maximum
    if ($maxWarning -gt $GracePeriodMinutes) {
        throw "The largest WarningMinutes value ($maxWarning) cannot exceed GracePeriodMinutes ($GracePeriodMinutes)."
    }

    $deadline = (Get-Date).AddMinutes($GracePeriodMinutes)
    Write-GentleLogoffLog -Text "Gentle logoff started. Grace period ends at $($deadline.ToString('yyyy-MM-dd HH:mm:ss'))." -LogPath $LogPath

    $warningsSent = [System.Collections.Generic.HashSet[int]]::new()
    while ((Get-Date) -lt $deadline) {
        $remainingMinutes = [math]::Ceiling(($deadline - (Get-Date)).TotalMinutes)
        $sessions = Get-InteractiveSessions -ExcludeUsers $ExcludeUsers

        if ($sessions.Count -eq 0) {
            Write-GentleLogoffLog -Text 'No interactive user sessions remain.' -LogPath $LogPath
            return $true
        }

        $sessionSummary = ($sessions | ForEach-Object { "{0} (id {1}, {2})" -f $_.DisplayUser, $_.SessionId, $_.State }) -join '; '
        Write-GentleLogoffLog -Text ("Found {0} session(s): {1}" -f $sessions.Count, $sessionSummary) -LogPath $LogPath

        foreach ($warningMinute in $WarningMinutes) {
            if ($warningsSent.Contains($warningMinute)) {
                continue
            }

            if ($remainingMinutes -le $warningMinute) {
                $minutesLeft = [math]::Max($remainingMinutes, 1)
                $warningText = "$Message`n`nLogoff in approximately $minutesLeft minute(s). The server will reboot after users are logged off."
                Write-GentleLogoffLog -Text "Sending T-$warningMinute minute warning to $($sessions.Count) session(s)." -LogPath $LogPath

                foreach ($session in $sessions) {
                    if ($PSCmdlet.ShouldProcess($session.DisplayUser, 'Send logoff warning')) {
                        $null = Send-SessionMessage -SessionId $session.SessionId -Text $warningText -LogPath $LogPath
                    }
                }

                $null = $warningsSent.Add($warningMinute)
            }
        }

        Start-Sleep -Seconds 30
    }

    Write-GentleLogoffLog -Text 'Grace period elapsed. Requesting graceful logoff for remaining sessions.' -LogPath $LogPath

    $sessions = Get-InteractiveSessions -ExcludeUsers $ExcludeUsers
    foreach ($session in $sessions) {
        Write-GentleLogoffLog -Text "Logging off $($session.DisplayUser) (session $($session.SessionId), $($session.State))." -LogPath $LogPath
        $null = Invoke-SessionLogoff -SessionId $session.SessionId -LogPath $LogPath
    }

    Start-Sleep -Seconds 15

    $remaining = Get-InteractiveSessions -ExcludeUsers $ExcludeUsers
    if ($remaining.Count -gt 0) {
        $summary = ($remaining | ForEach-Object { $_.DisplayUser }) -join ', '
        Write-GentleLogoffLog -Text "Logoff incomplete. Still logged on: $summary" -Level WARN -LogPath $LogPath
        return $false
    }

    Write-GentleLogoffLog -Text 'All interactive users logged off successfully.' -LogPath $LogPath
    return $true
}
