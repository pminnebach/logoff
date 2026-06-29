function Initialize-WtsNative {
    [CmdletBinding()]
    param()

    if ('WtsNative' -as [type]) {
        return
    }

    $wtsSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public class WtsSessionInfo
{
    public int SessionId { get; set; }
    public string SessionName { get; set; }
    public string UserName { get; set; }
    public string DomainName { get; set; }
    public string State { get; set; }
}

public static class WtsNative
{
    private const int WTSUserName = 5;
    private const int WTSDomainName = 7;

    [StructLayout(LayoutKind.Sequential)]
    private struct WTS_SESSION_INFO
    {
        public IntPtr pWinStationName;
        public int SessionID;
        public int State;
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSEnumerateSessions(
        IntPtr hServer,
        int Reserved,
        int Version,
        out IntPtr ppSessionInfo,
        out int pCount);

    [DllImport("wtsapi32.dll")]
    private static extern void WTSFreeMemory(IntPtr memory);

    [DllImport("wtsapi32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern bool WTSQuerySessionInformation(
        IntPtr hServer,
        int sessionId,
        int wtsInfoClass,
        out IntPtr ppBuffer,
        out int pBytesReturned);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSLogoffSession(
        IntPtr hServer,
        int sessionId,
        bool bWait);

    private static string GetStateName(int state)
    {
        switch (state)
        {
            case 0: return "WTSActive";
            case 1: return "WTSConnected";
            case 4: return "WTSDisconnected";
            case 5: return "WTSIdle";
            default: return state.ToString();
        }
    }

    private static bool IsInteractiveState(int state)
    {
        return state == 0 || state == 1 || state == 4 || state == 5;
    }

    private static string QuerySessionString(int sessionId, int infoClass)
    {
        IntPtr buffer;
        int bytes;

        if (!WTSQuerySessionInformation(IntPtr.Zero, sessionId, infoClass, out buffer, out bytes))
        {
            return null;
        }

        try
        {
            return buffer == IntPtr.Zero ? null : Marshal.PtrToStringAnsi(buffer);
        }
        finally
        {
            if (buffer != IntPtr.Zero)
            {
                WTSFreeMemory(buffer);
            }
        }
    }

    public static WtsSessionInfo[] EnumerateInteractiveSessions()
    {
        var results = new List<WtsSessionInfo>();
        IntPtr sessionInfoPtr;
        int count;

        if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out sessionInfoPtr, out count))
        {
            int error = Marshal.GetLastWin32Error();
            string message = new Win32Exception(error).Message;
            throw new InvalidOperationException(
                string.Format("WTSEnumerateSessions failed. Win32 error: {0}", message));
        }

        try
        {
            int structSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
            for (int i = 0; i < count; i++)
            {
                IntPtr current = new IntPtr(sessionInfoPtr.ToInt64() + (i * structSize));
                WTS_SESSION_INFO info = (WTS_SESSION_INFO)Marshal.PtrToStructure(current, typeof(WTS_SESSION_INFO));

                if (info.SessionID == 0 || !IsInteractiveState(info.State))
                {
                    continue;
                }

                string userName = QuerySessionString(info.SessionID, WTSUserName);
                if (string.IsNullOrWhiteSpace(userName))
                {
                    continue;
                }

                string domainName = QuerySessionString(info.SessionID, WTSDomainName);
                string sessionName = info.pWinStationName == IntPtr.Zero
                    ? null
                    : Marshal.PtrToStringAnsi(info.pWinStationName);

                results.Add(new WtsSessionInfo
                {
                    SessionId = info.SessionID,
                    SessionName = sessionName,
                    UserName = userName,
                    DomainName = domainName,
                    State = GetStateName(info.State)
                });
            }
        }
        finally
        {
            WTSFreeMemory(sessionInfoPtr);
        }

        return results.ToArray();
    }

    public static bool LogoffSession(int sessionId)
    {
        return WTSLogoffSession(IntPtr.Zero, sessionId, false);
    }
}
'@

    Add-Type -TypeDefinition $wtsSource -ErrorAction Stop
}
