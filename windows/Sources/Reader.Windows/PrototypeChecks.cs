using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Interop;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Qingdu.Windows;

internal static class PrototypeChecks
{
    internal static void VerifyHiddenStartup(ReadingWindow window)
    {
        IntPtr handle = new WindowInteropHelper(window).Handle;
        Check(handle != IntPtr.Zero && !window.IsVisible && !IsWindowVisible(handle) && !window.IsActive,
            "hidden startup before explicit restore");
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr handle);

    internal static async Task RunAsync(ReadingWindow window, WebView2CompositionControl browser, string script)
    {
        var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var core = browser.CoreWebView2;
        core.NavigationCompleted += (_, e) => loaded.TrySetResult(e.IsSuccess);
        core.Navigate(ReadingWindow.FixtureUrl);
        Check(await loaded.Task.WaitAsync(TimeSpan.FromSeconds(20)), "fixture navigation");
        await core.ExecuteScriptAsync(script);
        string result = await core.ExecuteScriptAsync("""
            (() => {
              const text = document.querySelector('#text'), style = getComputedStyle(text);
              document.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight'}));
              return style.color === 'rgb(212, 175, 55)' &&
                style.fontFamily.includes('Microsoft YaHei') &&
                window.firstLayout.font === style.fontFamily &&
                window.firstLayout.height === style.lineHeight &&
                window.firstLayout.margin === style.marginBottom &&
                parseFloat(style.lineHeight) === 22 * 1.55 &&
                getComputedStyle(document.querySelector('.renderTarget_pager_button')).display === 'none' &&
                getComputedStyle(document.querySelector('.readerTopBar')).visibility === 'hidden' &&
                getComputedStyle(document.querySelector('#outside')).color === 'rgb(20, 40, 60)' &&
                document.querySelectorAll('#qingdu-appearance').length === 1 &&
                document.querySelectorAll('#qingdu-text-filters').length === 1 && window.turns === 1;
            })()
            """);
        Check(result == "true", "DOM appearance and first measurement");
        // Allow a composition frame before capturing. This is a one-shot test delay, not app polling.
        await Task.Delay(250);
        using var pixels = new MemoryStream();
        await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, pixels);
        pixels.Position = 0;
        using var bitmap = new Bitmap(pixels);
        string widthJson = await core.ExecuteScriptAsync("innerWidth");
        double scale = bitmap.Width / double.Parse(widthJson, System.Globalization.CultureInfo.InvariantCulture);
        var gold = bitmap.GetPixel((int)(60 * scale), (int)(370 * scale));
        var reference = bitmap.GetPixel((int)(185 * scale), (int)(370 * scale));
        Check(Math.Abs(gold.R - reference.R) < 6 && Math.Abs(gold.G - reference.G) < 6 &&
            Math.Abs(gold.B - reference.B) < 6 && gold.A > 240, "canvas gold pixels");
        Check(bitmap.GetPixel(bitmap.Width - 5, bitmap.Height - 5).A == 0, "WebView transparent pixels");

        var busy = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var idle = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        core.WebMessageReceived += (_, e) =>
        {
            if (e.Source != ReadingWindow.FixtureUrl) return;
            string message = e.TryGetWebMessageAsString();
            if (message == "busy") busy.TrySetResult(true);
            if (message == "idle") idle.TrySetResult(true);
        };
        Task execution = core.ExecuteScriptAsync("setTimeout(window.startBusy, 0)");
        await busy.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await Task.Delay(100);
        Check(!idle.Task.IsCompleted, "page is busy before hide");
        var timer = Stopwatch.StartNew();
        window.ToggleVisibility();
        timer.Stop();
        Check(!window.IsVisible && timer.ElapsedMilliseconds < 500 && !idle.Task.IsCompleted, "native hide while busy");
        Console.WriteLine($"Native hide: {timer.Elapsed.TotalMilliseconds:F2} ms (not end-to-end keyboard latency)");
        window.Restore();
        Check(window.IsVisible, "restore");
        await execution.WaitAsync(TimeSpan.FromSeconds(5));
        await idle.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Console.WriteLine("PASS: offline prototype checks; desktop composition and input still require manual verification.");
    }

    private static void Check(bool passed, string name)
    {
        Console.WriteLine((passed ? "PASS: " : "FAIL: ") + name);
        if (!passed) throw new InvalidOperationException("Prototype check failed");
    }
}
