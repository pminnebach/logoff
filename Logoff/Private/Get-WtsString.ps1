function Get-WtsString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [IntPtr] $Buffer
    )

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
