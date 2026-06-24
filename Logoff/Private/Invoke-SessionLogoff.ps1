function Invoke-SessionLogoff {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [int] $SessionId,

        [string] $LogPath
    )

    if ($PSCmdlet.ShouldProcess("session $SessionId", 'Log off')) {
        $ok = [WtsNative]::LogoffSession($SessionId)
        if (-not $ok) {
            $errorText = [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message
            Write-GentleLogoffLog -Text "WTSLogoffSession failed for session ${SessionId}: $errorText" -Level ERROR -LogPath $LogPath
            return $false
        }
    }

    return $true
}
