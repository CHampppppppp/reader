using System;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using Forms = System.Windows.Forms;

namespace Qingdu.Windows;

internal sealed class ReadingWindow : Window
{
    internal const string FixtureUrl = "https://weread.qq.com/web/reader/qingdu-local-fixture";
    private readonly bool website;
    private readonly bool selfTest;
    private readonly WebView2CompositionControl browser = new();
    private readonly System.Drawing.Icon appIcon;
    private readonly Forms.NotifyIcon tray;
    private readonly Forms.ToolStripItem? homeMenuItem;
    private GlobalHotKey? hotKey;
    private GlobalHotKey? homeHotKey;
    private bool homeHotKeyWarningShown;
    private Point? dragStart;
    private bool exiting;
    private bool closed;
    private bool initializationStarted;

    internal ReadingWindow(bool website, bool selfTest)
    {
        this.website = website;
        this.selfTest = selfTest;
        appIcon = new System.Drawing.Icon(Path.Combine(AppContext.BaseDirectory, "Resources", "AppIcon.ico"));
        Title = "轻读 Windows 原型";
        Width = 760;
        Height = 620;
        MinWidth = 420;
        MinHeight = 320;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.CanResizeWithGrip;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        browser.DefaultBackgroundColor = System.Drawing.Color.Transparent;
        Content = browser;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示 / 隐藏（Alt + 0）", null, (_, _) => ToggleVisibility());
        if (website)
        {
            homeMenuItem = menu.Items.Add("返回选书页（Alt + Esc）", null, (_, _) => ReturnToBooks());
            homeMenuItem.Enabled = false;
        }
        menu.Items.Add("切换深色底 / 透明底", null, (_, _) =>
            Background = Background == Brushes.Transparent ? new SolidColorBrush(Color.FromRgb(28, 28, 30)) : Brushes.Transparent);
        menu.Items.Add("退出轻读", null, (_, _) => Exit(0));
        tray = new Forms.NotifyIcon
        {
            Icon = appIcon,
            Text = "轻读 Windows 原型",
            ContextMenuStrip = menu,
            Visible = !selfTest
        };
        tray.DoubleClick += (_, _) => Restore();
        SourceInitialized += (_, _) =>
        {
            if (selfTest) return; // Automated runs must not steal a user's shortcut.
            IntPtr handle = new WindowInteropHelper(this).Handle;
            // MOD_ALT | MOD_NOREPEAT, main keyboard 0.
            hotKey = new GlobalHotKey(handle, 0x5144, 0x4001, 0x30, ToggleVisibility);
            if (!hotKey.IsRegistered)
            {
                tray.Text = "轻读：Alt + 0 已被占用，请用托盘显示";
                tray.ShowBalloonTip(5000, Title, "Alt + 0 已被占用，使用托盘菜单显示或隐藏。", Forms.ToolTipIcon.Warning);
            }
            if (website)
            {
                // Alt+Esc also cycles Windows windows; reserve it only while this window is active.
                homeHotKey = new GlobalHotKey(handle, 0x5145, 0x4001, 0x1B, ReturnToBooks, registerImmediately: false);
                if (IsActive) RegisterHomeHotKey();
            }
        };
        Activated += (_, _) => RegisterHomeHotKey();
        Deactivated += (_, _) => homeHotKey?.Unregister();
        PreviewMouseLeftButtonDown += (_, e) =>
        {
            dragStart = (Keyboard.Modifiers & ModifierKeys.Alt) != 0 ? e.GetPosition(this) : null;
        };
        PreviewMouseMove += (_, e) =>
        {
            if (dragStart is not Point start) return;
            if (e.LeftButton != MouseButtonState.Pressed || (Keyboard.Modifiers & ModifierKeys.Alt) == 0)
            {
                dragStart = null;
                return;
            }
            Point current = e.GetPosition(this);
            if (Math.Abs(current.X - start.X) < SystemParameters.MinimumHorizontalDragDistance &&
                Math.Abs(current.Y - start.Y) < SystemParameters.MinimumVerticalDragDistance) return;
            dragStart = null;
            e.Handled = true;
            DragMove();
        };
        PreviewMouseLeftButtonUp += (_, _) => dragStart = null;
        Loaded += async (_, _) =>
        {
            if (initializationStarted) return;
            initializationStarted = true;
            await InitializeAsync();
        };
    }

    internal void Start()
    {
        // Create only the native handle for global hotkeys; never flash or focus the window.
        new WindowInteropHelper(this).EnsureHandle();
        if (!selfTest) return;
        try
        {
            PrototypeChecks.VerifyHiddenStartup(this);
            Restore();
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("FAIL: " + error.GetType().Name);
            Exit(1);
        }
    }

    private async Task InitializeAsync()
    {
        try
        {
            string profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Qingdu", website ? "WebView2" : "Prototype", website ? "Profile" : Guid.NewGuid().ToString("N"));
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile);
            if (closed) return;
            await browser.EnsureCoreWebView2Async(environment);
            if (closed) return;
            var core = browser.CoreWebView2;
            if (homeMenuItem is not null) homeMenuItem.Enabled = true;
            core.Settings.IsWebMessageEnabled = !website;
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.NavigationStarting += (_, e) =>
            {
                if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                    uri.Host != "weread.qq.com" || uri.Port != 443 || uri.UserInfo.Length != 0 ||
                    (!website && e.Uri != FixtureUrl)) e.Cancel = true;
            };
            string script = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Resources", "appearance.js"));
            if (closed) return;
            script = script.Replace("__READER_SETTINGS__", "{transparent:true,opacity:0}");
            await core.AddScriptToExecuteOnDocumentCreatedAsync("if (window.top === window) {" + script + "}");
            if (closed) return;
            browser.ZoomFactor = 1;
            if (!website)
            {
                string fixture = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Resources", "Fixture.html"));
                if (closed) return;
                core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                core.WebResourceRequested += (_, e) =>
                {
                    bool isFixture = e.Request.Uri == FixtureUrl;
                    e.Response = environment.CreateWebResourceResponse(
                        new MemoryStream(Encoding.UTF8.GetBytes(isFixture ? fixture : "")),
                        isFixture ? 200 : 403, isFixture ? "OK" : "Blocked",
                        "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
                };
            }
            if (selfTest)
            {
                await PrototypeChecks.RunAsync(this, browser, script);
                Exit(0);
            }
            else core.Navigate(website ? "https://weread.qq.com/" : FixtureUrl);
        }
        catch (Exception error)
        {
            if (closed) return;
            if (selfTest)
            {
                // Only a type name is emitted: exception messages can contain profile paths or URLs.
                Console.Error.WriteLine("FAIL: " + error.GetType().Name);
                Exit(1);
            }
            else
            {
                MessageBox.Show(this, error is WebView2RuntimeNotFoundException
                    ? "未找到 WebView2 Runtime。请从微软官网安装 Evergreen Runtime 后重试。"
                    : "原型加载失败，请检查 WebView2 Runtime 与 Resources 文件。错误类型：" + error.GetType().Name, Title);
                Exit(1);
            }
        }
    }

    internal void ToggleVisibility()
    {
        if (IsVisible)
        {
            Hide(); // Native removal first; never wait for JavaScript.
            homeHotKey?.Unregister();
        }
        else Restore();
    }

    private void RegisterHomeHotKey()
    {
        if (homeHotKey is null || !IsActive || homeHotKey.Register() || homeHotKeyWarningShown) return;
        homeHotKeyWarningShown = true;
        MessageBox.Show(this, "Alt + Esc 已被占用，请使用托盘菜单返回选书页。", Title);
    }

    internal void Restore()
    {
        Show();
        Activate();
        browser.Focus();
    }

    internal void ReturnToBooks()
    {
        if (!website || browser.CoreWebView2 is not { } core) return;
        core.Navigate("https://weread.qq.com/");
        Restore();
    }

    internal void Exit(int code)
    {
        exiting = true;
        Application.Current.Shutdown(code);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!exiting) { e.Cancel = true; Hide(); homeHotKey?.Unregister(); }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        closed = true;
        hotKey?.Dispose();
        homeHotKey?.Dispose();
        tray.Visible = false;
        tray.ContextMenuStrip?.Dispose();
        tray.Dispose();
        appIcon.Dispose();
        browser.Dispose();
        base.OnClosed(e);
    }
}
