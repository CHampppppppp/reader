using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Qingdu.Windows;

internal sealed class GlobalHotKey : IDisposable
{
    private readonly HwndSource source;
    private readonly int id;
    private readonly uint modifiers;
    private readonly uint key;
    private readonly Action onPress;
    public bool IsRegistered { get; private set; }

    public GlobalHotKey(IntPtr handle, int id, uint modifiers, uint key, Action onPress, bool registerImmediately = true)
    {
        this.id = id;
        this.modifiers = modifiers;
        this.key = key;
        this.onPress = onPress;
        source = HwndSource.FromHwnd(handle) ?? throw new InvalidOperationException("Missing window handle");
        source.AddHook(HandleMessage);
        if (registerImmediately) Register();
    }

    public bool Register()
    {
        if (IsRegistered) return true;
        IsRegistered = RegisterHotKey(source.Handle, id, modifiers, key);
        return IsRegistered;
    }

    public void Unregister()
    {
        if (!IsRegistered) return;
        UnregisterHotKey(source.Handle, id);
        IsRegistered = false;
    }

    private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == 0x0312 && wParam.ToInt32() == id && IsRegistered)
        {
            handled = true;
            onPress();
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        Unregister();
        source.RemoveHook(HandleMessage);
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
}
