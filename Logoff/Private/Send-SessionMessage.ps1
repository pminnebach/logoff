function Send-SessionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $SessionId,

        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter()]
        [int] $DisplaySeconds = 60,

        [string] $LogPath
    )

    $escaped = $Text -replace '"', '\"'
    $arguments = @(
        $SessionId
        '/TIME:' + $DisplaySeconds
        "`"$escaped`""
    )

    $process = Start-Process -FilePath 'msg.exe' -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        Write-GentleLogoffLog -Text "msg.exe returned exit code $($process.ExitCode) for session $SessionId" -Level WARN -LogPath $LogPath
        return $false
    }

    return $true
}
