function Get-InteractiveSessions {
    [CmdletBinding()]
    param(
        [string[]] $ExcludeUsers = @()
    )

    $sessions = [WtsNative]::EnumerateInteractiveSessions() | ForEach-Object {
        [pscustomobject]@{
            SessionId   = $_.SessionId
            SessionName = $_.SessionName
            UserName    = $_.UserName
            DomainName  = $_.DomainName
            State       = $_.State
            DisplayUser = if ($_.DomainName) { "$($_.DomainName)\$($_.UserName)" } else { $_.UserName }
        }
    }

    if ($ExcludeUsers.Count -gt 0) {
        $excluded = $ExcludeUsers | ForEach-Object { $_.ToLowerInvariant() }
        return @($sessions | Where-Object { $_.UserName.ToLowerInvariant() -notin $excluded })
    }

    return @($sessions)
}
