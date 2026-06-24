function Get-InteractiveSessions {
    [CmdletBinding()]
    param(
        [string[]] $ExcludeUsers = @()
    )

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
                    SessionId   = $info.SessionID
                    SessionName = $info.pWinStationName
                    UserName    = $userName
                    DomainName  = $domainName
                    State       = $state.ToString()
                    DisplayUser = if ($domainName) { "$domainName\$userName" } else { $userName }
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
