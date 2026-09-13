using System.Diagnostics;
using System.Runtime.InteropServices;

internal static class StartupFailureProcess
{
    public static Process Start(ProcessStartInfo startInfo)
    {
        if (!OperatingSystem.IsWindows())
            return Process.Start(startInfo) ?? throw new InvalidOperationException("Failed to start Rover.Api.");

        // Expected unhandled startup errors must not wait for Windows crash-report UI.
        // Child processes inherit this mode; restore the test runner immediately.
        var previous = GetErrorMode();
        SetErrorMode(previous | 0x0002);
        try
        {
            return Process.Start(startInfo) ?? throw new InvalidOperationException("Failed to start Rover.Api.");
        }
        finally
        {
            SetErrorMode(previous);
        }
    }

    [DllImport("kernel32.dll")]
    private static extern uint GetErrorMode();

    [DllImport("kernel32.dll")]
    private static extern uint SetErrorMode(uint mode);
}
