using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Qingdu.Windows;

internal sealed class GlobalHotKey : IDisposable
{
    private const int Id = 0x5144;
    private readonly HwndSource source;
    private readonly Action onPress;
    public bool IsRegistered { get; }

    public GlobalHotKey(IntPtr handle, Action onPress)
    {
        this.onPress = onPress;
        source = HwndSource.FromHwnd(handle) ?? throw new InvalidOperationException("Missing window handle");
        source.AddHook(HandleMessage);
        // MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, main keyboard 0.
        IsRegistered = RegisterHotKey(handle, Id, 0x4003, 0x30);
    }

    private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x0312 && wParam.ToInt32() == Id && IsRegistered)
        {
            handled = true;
            onPress();
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (IsRegistered) UnregisterHotKey(source.Handle, Id);
        source.RemoveHook(HandleMessage);
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}
