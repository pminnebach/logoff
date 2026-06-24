#Requires -Version 5.1
function Get-LoggedOnSession {
    <#
    .SYNOPSIS
        Lists interactive user sessions on the local Windows server.

    .DESCRIPTION
        Returns logged-on users and their session details (session ID, session name,
        domain, username, and connection state). Non-interactive sessions such as
        session 0 and listener sessions are omitted.

    .PARAMETER ExcludeUsers
        SAM account names to omit from the results (case-insensitive).

    .OUTPUTS
        PSCustomObject with SessionId, SessionName, UserName, DomainName, State, and DisplayUser.

    .EXAMPLE
        Get-LoggedOnSession

    .EXAMPLE
        Get-LoggedOnSession | Format-Table SessionId, DisplayUser, State, SessionName -AutoSize

    .EXAMPLE
        Get-LoggedOnSession -ExcludeUsers 'Administrator'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string[]] $ExcludeUsers = @()
    )

    Initialize-WtsNative
    Get-InteractiveSessions -ExcludeUsers $ExcludeUsers
}
