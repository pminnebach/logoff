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

function Initialize-WtsNative {
    [CmdletBinding()]
    param()

    if ('WtsNative' -as [type]) {
        return
    }

    $wtsSource = @'
using System;
using System.Runtime.InteropServices;

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
