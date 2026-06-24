#Requires -Version 5.1
#Requires -RunAsAdministrator
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

.PARAMETER WhatIf
    Report actions without sending messages or logging anyone off.

.EXAMPLE
    .\Invoke-GentleLogoff.ps1 -GracePeriodMinutes 15 -WarningMinutes 15,5,1

.EXAMPLE
    .\Invoke-GentleLogoff.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region WTS API

enum WTS_CONNECTSTATE_CLASS {
    WTSActive = 0
    WTSConnected = 1
    WTSConnectQuery = 2
    WTSShadow = 3
    WTSDisconnected = 4
    WTSIdle = 5
    WTSListen = 6
    WTSReset = 7
    WTSDown = 8
    WTSInit = 9
}

enum WTS_INFO_CLASS {
    WTSUserName = 5
    WTSDomainName = 7
}

if (-not ('WtsNative' -as [type])) {
    $wtsSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WtsNative
{
    public const int WTS_CURRENT_SERVER_HANDLE = 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO
    {
        public int SessionID;
        [MarshalAs(UnmanagedType.LPStr)]
        public string pWinStationName;
        public int State;
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern int WTSEnumerateSessions(
        IntPtr hServer,
        int Reserved,
        int Version,
        out IntPtr ppSessionInfo,
        out int pCount);

    [DllImport("wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool WTSQuerySessionInformation(
        IntPtr hServer,
        int sessionId,
        int wtsInfoClass,
        out IntPtr ppBuffer,
        out int pBytesReturned);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSLogoffSession(
        IntPtr hServer,
        int SessionId,
        bool bWait);
}
'@
    Add-Type -TypeDefinition $wtsSource -ErrorAction Stop
}

#endregion

#region Helpers

function Write-Log {
    param(
        [string] $Text,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level = 'INFO'
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Text
    Write-Host $line

    if ($LogPath) {
        $directory = Split-Path -Parent $LogPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Get-WtsString {
    param([IntPtr] $Buffer)

    if ($Buffer -eq [IntPtr]::Zero) {
        return $null
    }

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAnsi($Buffer)
    }
    finally {
        [WtsNative]::WTSFreeMemory($Buffer) | Out-Null
    }
}

function Get-InteractiveSessions {
    $sessions = New-Object System.Collections.Generic.List[object]
    $ptr = [IntPtr]::Zero
    $count = 0

    $result = [WtsNative]::WTSEnumerateSessions(
        [IntPtr]::new([WtsNative]::WTS_CURRENT_SERVER_HANDLE),
        0,
        1,
        [ref] $ptr,
        [ref] $count)

    if ($result -eq 0) {
        throw "WTSEnumerateSessions failed. Win32 error: $([ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message)"
    }

    try {
        $structSize = [Runtime.InteropServices.Marshal]::SizeOf([type][WtsNative+WTS_SESSION_INFO])
        for ($i = 0; $i -lt $count; $i++) {
            $current = [IntPtr]::Add($ptr, $i * $structSize)
            $info = [Runtime.InteropServices.Marshal]::PtrToStructure($current, [type][WtsNative+WTS_SESSION_INFO])

            if ($info.SessionID -eq 0) {
                continue
            }

            $state = [WTS_CONNECTSTATE_CLASS] $info.State
            $interactiveStates = @(
                [WTS_CONNECTSTATE_CLASS]::WTSActive
                [WTS_CONNECTSTATE_CLASS]::WTSConnected
                [WTS_CONNECTSTATE_CLASS]::WTSDisconnected
                [WTS_CONNECTSTATE_CLASS]::WTSIdle
            )
            if ($state -notin $interactiveStates) {
                continue
            }

            $userBuffer = [IntPtr]::Zero
            $bytes = 0
            $userName = $null
            if ([WtsNative]::WTSQuerySessionInformation(
                    [IntPtr]::Zero,
                    $info.SessionID,
                    [int][WTS_INFO_CLASS]::WTSUserName,
                    [ref] $userBuffer,
                    [ref] $bytes)) {
                $userName = Get-WtsString -Buffer $userBuffer
            }

            if ([string]::IsNullOrWhiteSpace($userName)) {
                continue
            }

            $domainBuffer = [IntPtr]::Zero
            $domainName = $null
            if ([WtsNative]::WTSQuerySessionInformation(
                    [IntPtr]::Zero,
                    $info.SessionID,
                    [int][WTS_INFO_CLASS]::WTSDomainName,
                    [ref] $domainBuffer,
                    [ref] $bytes)) {
                $domainName = Get-WtsString -Buffer $domainBuffer
            }

            $sessions.Add([pscustomobject]@{
                    SessionId     = $info.SessionID
                    SessionName   = $info.pWinStationName
                    UserName      = $userName
                    DomainName    = $domainName
                    State         = $state.ToString()
                    DisplayUser   = if ($domainName) { "$domainName\$userName" } else { $userName }
                })
        }
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [WtsNative]::WTSFreeMemory($ptr) | Out-Null
        }
    }

    if ($ExcludeUsers.Count -gt 0) {
        $excluded = $ExcludeUsers | ForEach-Object { $_.ToLowerInvariant() }
        return @($sessions | Where-Object { $_.UserName.ToLowerInvariant() -notin $excluded })
    }

    return @($sessions)
}

function Send-SessionMessage {
    param(
        [Parameter(Mandatory)]
        [int] $SessionId,

        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter()]
        [int] $DisplaySeconds = 60
    )

    # msg.exe accepts a session ID and shows a timed modal dialog on the user's desktop.
    $escaped = $Text -replace '"', '\"'
    $arguments = @(
        $SessionId
        '/TIME:' + $DisplaySeconds
        "`"$escaped`""
    )

    $process = Start-Process -FilePath 'msg.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        Write-Log "msg.exe returned exit code $($process.ExitCode) for session $SessionId" 'WARN'
        return $false
    }

    return $true
}

function Invoke-SessionLogoff {
    param(
        [Parameter(Mandatory)]
        [int] $SessionId
    )

    if ($WhatIfPreference) {
        Write-Log "WhatIf: would log off session $SessionId" 'INFO'
        return $true
    }

    $ok = [WtsNative]::WTSLogoffSession([IntPtr]::Zero, $SessionId, $false)
    if (-not $ok) {
        $errorText = [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
        Write-Log "WTSLogoffSession failed for session ${SessionId}: $errorText" 'ERROR'
        return $false
    }

    return $true
}

#endregion

#region Main

$WarningMinutes = @($WarningMinutes | Sort-Object -Descending -Unique)
$maxWarning = ($WarningMinutes | Measure-Object -Maximum).Maximum
if ($maxWarning -gt $GracePeriodMinutes) {
    throw "The largest WarningMinutes value ($maxWarning) cannot exceed GracePeriodMinutes ($GracePeriodMinutes)."
}

$deadline = (Get-Date).AddMinutes($GracePeriodMinutes)
Write-Log "Gentle logoff started. Grace period ends at $($deadline.ToString('yyyy-MM-dd HH:mm:ss'))." 'INFO'

$warningsSent = [System.Collections.Generic.HashSet[int]]::new()
while ((Get-Date) -lt $deadline) {
    $remainingMinutes = [math]::Ceiling(($deadline - (Get-Date)).TotalMinutes)
    $sessions = Get-InteractiveSessions

    if ($sessions.Count -eq 0) {
        Write-Log 'No interactive user sessions remain.' 'INFO'
        return 0
    }

    Write-Log ("Found {0} session(s): {1}" -f $sessions.Count, (($sessions | ForEach-Object { "{0} (id {1}, {2})" -f $_.DisplayUser, $_.SessionId, $_.State }) -join '; ')) 'INFO'

    foreach ($warningMinute in $WarningMinutes) {
        if ($warningsSent.Contains($warningMinute)) {
            continue
        }

        if ($remainingMinutes -le $warningMinute) {
            $minutesLeft = [math]::Max($remainingMinutes, 1)
            $warningText = "$Message`n`nLogoff in approximately $minutesLeft minute(s). The server will reboot after users are logged off."
            Write-Log "Sending T-$warningMinute minute warning to $($sessions.Count) session(s)." 'INFO'

            foreach ($session in $sessions) {
                if ($PSCmdlet.ShouldProcess($session.DisplayUser, 'Send logoff warning')) {
                    $null = Send-SessionMessage -SessionId $session.SessionId -Text $warningText -DisplaySeconds 60
                }
            }

            $null = $warningsSent.Add($warningMinute)
        }
    }

    Start-Sleep -Seconds 30
}

Write-Log 'Grace period elapsed. Requesting graceful logoff for remaining sessions.' 'INFO'

$failures = 0
$sessions = Get-InteractiveSessions
foreach ($session in $sessions) {
    Write-Log "Logging off $($session.DisplayUser) (session $($session.SessionId), $($session.State))." 'INFO'
    if (-not (Invoke-SessionLogoff -SessionId $session.SessionId)) {
        $failures++
    }
}

# Allow logoff handlers a short time to run (apps saving, profile unload).
Start-Sleep -Seconds 15

$remaining = Get-InteractiveSessions
if ($remaining.Count -gt 0) {
    $summary = ($remaining | ForEach-Object { $_.DisplayUser }) -join ', '
    Write-Log "Logoff incomplete. Still logged on: $summary" 'WARN'
    exit 1
}

Write-Log 'All interactive users logged off successfully.' 'INFO'
exit 0

#endregion
