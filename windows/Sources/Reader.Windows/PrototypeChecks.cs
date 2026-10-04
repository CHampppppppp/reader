using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Interop;
using System.Windows.Input;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Qingdu.Windows;

internal static class PrototypeChecks
{
    internal static void VerifyHiddenStartup(ReadingWindow window)
    {
        Check(ReaderKeys.VisibilityKey == 0x26 && ReaderKeys.VisibilityModifiers == 0x4002,
            "Ctrl + Up Arrow global binding with repeat suppression");
        Check(ReaderKeys.HidesReader(Key.Up, ModifierKeys.None, true), "focused Up hides");
        Check(!ReaderKeys.HidesReader(Key.Up, ModifierKeys.None, false), "inactive Up does not hide");
        Check(!ReaderKeys.HidesReader(Key.Up, ModifierKeys.Control, true), "Ctrl Up remains global");
        Check(!ReaderKeys.HidesReader(Key.Left, ModifierKeys.None, true), "Left remains page input");
        Check(ReaderKeys.ReturnsToBooks(Key.Down, ModifierKeys.None, true), "plain Down returns while active");
        foreach (var key in new[] { Key.Left, Key.Right, Key.Up, Key.Escape })
            Check(!ReaderKeys.ReturnsToBooks(key, ModifierKeys.None, true), "other keys pass to webpage");
        foreach (var modifier in new[] { ModifierKeys.Alt, ModifierKeys.Control, ModifierKeys.Shift, ModifierKeys.Windows })
            Check(!ReaderKeys.ReturnsToBooks(Key.Down, modifier, true), "modified Down is not intercepted");
        Check(!ReaderKeys.ReturnsToBooks(Key.Down, ModifierKeys.None, false), "inactive window does not return");
        var wheel = new WheelPagingState();
        Check(wheel.Consume(-60, 1, true) is null && wheel.Consume(-60, 1.1, true) == 1, "wheel accumulation and next");
        wheel.ClearMotion();
        Check(wheel.Consume(-120, 1.2, true) is null, "wheel throttle");
        Check(wheel.Consume(120, 2, true) == -1, "wheel previous");
        Check(wheel.Consume(-120, 3, false) is null, "unfocused wheel ignored");
        string path = Path.Combine(Path.GetTempPath(), "qingdu-paging-" + Guid.NewGuid().ToString("N"), "mode.txt");
        var paging = new PagingPreferences(path);
        Check(!paging.Wheel, "default keyboard paging");
        paging.Save(true);
        Check(new PagingPreferences(path).Wheel, "wheel preference persists");
        paging.Save(false);
        Check(!new PagingPreferences(path).Wheel, "keyboard preference persists");
        IntPtr handle = new WindowInteropHelper(window).Handle;
        Check(handle != IntPtr.Zero && !window.IsVisible && !IsWindowVisible(handle) && !window.IsActive,
            "hidden startup before explicit restore");
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr handle);

    internal static async Task RunAsync(ReadingWindow window, WebView2CompositionControl browser, string script)
    {
        VerifyColorPreferences();
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

        foreach (var color in ReadingColor.Choices)
        {
            await window.ChangeTextColorAsync(color);
            string colorResult = await core.ExecuteScriptAsync("""
                (() => {
                  document.querySelector('#reference').style.backgroundColor = 'COLOR';
                  const style = getComputedStyle(document.querySelector('#text'));
                  return style.color === getComputedStyle(document.querySelector('#reference')).backgroundColor &&
                    window.firstLayout.height === style.lineHeight && window.firstLayout.margin === style.marginBottom &&
                    getComputedStyle(document.querySelector('#outside')).color === 'rgb(20, 40, 60)' &&
                    getComputedStyle(document.querySelector('#illustration')).filter === 'none' &&
                    document.querySelectorAll('#qingdu-text-filters').length === 1;
                })()
                """.Replace("COLOR", color.Hex));
            Check(colorResult == "true", "changed DOM color and stable layout: " + color.Label);
            await Task.Delay(100);
            using var changedPixels = new MemoryStream();
            await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, changedPixels);
            changedPixels.Position = 0;
            using var changed = new Bitmap(changedPixels);
            var textPixel = changed.GetPixel((int)(60 * scale), (int)(370 * scale));
            var swatch = changed.GetPixel((int)(185 * scale), (int)(370 * scale));
            Check(Math.Abs(textPixel.R - swatch.R) < 6 && Math.Abs(textPixel.G - swatch.G) < 6 &&
                Math.Abs(textPixel.B - swatch.B) < 6 && textPixel.A > 240, "changed canvas pixels: " + color.Label);
            var illustration = changed.GetPixel((int)(225 * scale), (int)(370 * scale));
            var pictureReference = changed.GetPixel((int)(255 * scale), (int)(370 * scale));
            Check(Math.Abs(illustration.R - pictureReference.R) < 6 && Math.Abs(illustration.G - pictureReference.G) < 6 &&
                Math.Abs(illustration.B - pictureReference.B) < 6 && illustration.A > 240, "illustration retains original pixels");
        }
        var reloaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        core.NavigationCompleted += (_, e) => reloaded.TrySetResult(e.IsSuccess);
        core.Reload();
        Check(await reloaded.Task.WaitAsync(TimeSpan.FromSeconds(10)), "reload with selected color");
        Check(await core.ExecuteScriptAsync("window.firstLayout.color === 'rgb(130, 177, 255)'") == "true",
            "selected color installed before page script on next navigation");
        await core.ExecuteScriptAsync(script.Replace("\"textColor\":\"#D4AF37\"", "\"textColor\":\"invalid\""));
        Check(await core.ExecuteScriptAsync("getComputedStyle(document.querySelector('#text')).color === 'rgb(212, 175, 55)'") == "true",
            "invalid script color falls back to gold");

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

    private static void VerifyColorPreferences()
    {
        string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Qingdu", "PrototypeSettings", Guid.NewGuid().ToString("N"), "text-color.txt");
        var preferences = new ColorPreferences(path);
        Check(preferences.TextColor == ReadingColor.Choices[0], "default color is gold");
        foreach (var color in ReadingColor.Choices)
        {
            preferences.Save(color);
            Check(new ColorPreferences(path).TextColor == color, "saved color survives restart");
        }
        File.WriteAllText(path, "invalid");
        Check(new ColorPreferences(path).TextColor == ReadingColor.Choices[0], "invalid saved color falls back to gold");
    }

    private static void Check(bool passed, string name)
    {
        Console.WriteLine((passed ? "PASS: " : "FAIL: ") + name);
        if (!passed) throw new InvalidOperationException("Prototype check failed");
    }
}
