using System;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Controls;
using System.Windows.Automation;
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
    private readonly Forms.ToolStripMenuItem colorMenu;
    private readonly ColorPreferences colorPreferences;
    private readonly PagingPreferences pagingPreferences;
    private readonly Forms.ToolStripMenuItem pagingMenu = new("翻页方式");
    private readonly Button mouseCloseButton = new();
    private readonly WheelPagingState wheelState = new();
    private bool pageTurnPending;
    private string? appearanceTemplate;
    private string? appearanceScriptId;
    private GlobalHotKey? hotKey;
    private Point? dragStart;
    private bool exiting;
    private bool closed;
    private bool initializationStarted;

    internal ReadingWindow(bool website, bool selfTest)
    {
        this.website = website;
        this.selfTest = selfTest;
        string settingsDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Qingdu");
        if (selfTest) settingsDirectory = Path.Combine(settingsDirectory, "PrototypeSettings", Guid.NewGuid().ToString("N"));
        colorPreferences = new ColorPreferences(Path.Combine(settingsDirectory, "text-color.txt"));
        pagingPreferences = new PagingPreferences(Path.Combine(settingsDirectory, "page-turn-mode.txt"));
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
        var surface = new Grid();
        surface.Children.Add(browser);
        mouseCloseButton.Content = "×";
        mouseCloseButton.Width = mouseCloseButton.Height = 32;
        mouseCloseButton.FontSize = 20;
        mouseCloseButton.Margin = new Thickness(8);
        mouseCloseButton.HorizontalAlignment = HorizontalAlignment.Right;
        mouseCloseButton.VerticalAlignment = VerticalAlignment.Top;
        mouseCloseButton.ToolTip = "关闭阅读窗口（隐藏）";
        AutomationProperties.SetName(mouseCloseButton, "关闭阅读窗口（隐藏）");
        mouseCloseButton.Click += (_, _) => HideReader();
        surface.Children.Add(mouseCloseButton);
        Content = surface;
        browser.PreviewMouseWheel += OnMouseWheel;
        Deactivated += (_, _) => wheelState.Reset();
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示 / 隐藏（Ctrl + ↑）", null, (_, _) => ToggleVisibility()).ToolTipText = "全局 Ctrl + ↑ 显示／隐藏；按住只切换一次。";
        if (website)
        {
            homeMenuItem = menu.Items.Add("返回选书页（↓）", null, (_, _) => ReturnToBooks());
            homeMenuItem.Enabled = false;
        }
        menu.Items.Add("切换深色底 / 透明底", null, (_, _) =>
            Background = Background == Brushes.Transparent ? new SolidColorBrush(Color.FromRgb(28, 28, 30)) : Brushes.Transparent);
        colorMenu = new Forms.ToolStripMenuItem("字体颜色");
        foreach (var color in ReadingColor.Choices)
        {
            var choice = new Forms.ToolStripMenuItem(color.Label) { Tag = color };
            choice.Click += async (_, _) => await ChangeTextColorAsync(color);
            colorMenu.DropDownItems.Add(choice);
        }
        RefreshColorMenu();
        menu.Items.Add(colorMenu);
        foreach (bool wheel in new[] { false, true })
        {
            var item = new Forms.ToolStripMenuItem(wheel ? "鼠标滚轮翻页" : "方向键翻页") { Tag = wheel };
            item.Click += (_, _) => ChangePageTurnMode(wheel);
            pagingMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(pagingMenu);
        ApplyPageTurnMode();
        menu.Items.Add("退出轻读", null, (_, _) => Exit(0));
        tray = new Forms.NotifyIcon
        {
            Icon = appIcon,
            Text = "轻读 Windows 原型",
            ContextMenuStrip = menu,
            Visible = !selfTest
        };
        tray.DoubleClick += (_, _) => Restore();
        if (colorPreferences.LoadFailed && !selfTest)
            tray.ShowBalloonTip(5000, Title, "字体颜色设置读取失败，暂用金色。", Forms.ToolTipIcon.Warning);
        if (pagingPreferences.LoadFailed && !selfTest)
            tray.ShowBalloonTip(5000, Title, "翻页方式读取失败，暂用方向键。", Forms.ToolTipIcon.Warning);
        SourceInitialized += (_, _) =>
        {
            if (selfTest) return; // Automated runs must not steal a user's shortcut.
            IntPtr handle = new WindowInteropHelper(this).Handle;
            // Ctrl + Up Arrow, with native repeat suppression.
            hotKey = new GlobalHotKey(handle, 0x5144, ReaderKeys.VisibilityModifiers, ReaderKeys.VisibilityKey, ToggleVisibility);
            if (!hotKey.IsRegistered)
            {
                tray.Text = "轻读：Ctrl + ↑ 已被占用，请用托盘显示";
                tray.ShowBalloonTip(5000, Title, "Ctrl + ↑ 已被占用，使用托盘菜单显示或隐藏。", Forms.ToolTipIcon.Warning);
            }
        };
        PreviewKeyDown += (_, e) =>
        {
            if (!website || !ReaderKeys.ReturnsToBooks(e.Key, Keyboard.Modifiers, IsActive)) return;
            e.Handled = true;
            if (!e.IsRepeat)
            {
                // Leave WebView2's input callback before navigating. Do not reopen after a queued hide.
                Dispatcher.BeginInvoke(new Action(() => { if (!closed && IsActive) ReturnToBooks(); }));
            }
        };
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
                wheelState.Reset();
                if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                    uri.Host != "weread.qq.com" || uri.Port != 443 || uri.UserInfo.Length != 0 ||
                    (!website && e.Uri != FixtureUrl)) e.Cancel = true;
            };
            // Lock color changes while installing the initial document-created script.
            colorMenu.Enabled = false;
            appearanceTemplate = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Resources", "appearance.js"));
            if (closed) return;
            string script = BuildAppearanceScript(colorPreferences.TextColor);
            appearanceScriptId = await core.AddScriptToExecuteOnDocumentCreatedAsync(script);
            if (closed) return;
            colorMenu.Enabled = true;
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

    private string BuildAppearanceScript(ReadingColor color)
    {
        string settings = JsonSerializer.Serialize(new { transparent = true, opacity = 0, textColor = color.Hex });
        return "if (window.top === window) {" + appearanceTemplate!.Replace("__READER_SETTINGS__", settings) + "}";
    }

    internal async Task ChangeTextColorAsync(ReadingColor color)
    {
        if (closed || !colorMenu.Enabled) return;
        colorMenu.Enabled = false;
        bool saved = false;
        try
        {
            colorPreferences.Save(color);
            saved = true;
            RefreshColorMenu();
            if (appearanceTemplate is null || browser.CoreWebView2 is not { } core) return;
            string script = BuildAppearanceScript(colorPreferences.TextColor);
            string replacement = await core.AddScriptToExecuteOnDocumentCreatedAsync(script);
            if (closed) return;
            if (appearanceScriptId is not null) core.RemoveScriptToExecuteOnDocumentCreated(appearanceScriptId);
            appearanceScriptId = replacement;
            await core.ExecuteScriptAsync(script);
        }
        catch (Exception error)
        {
            if (closed) return;
            if (selfTest) throw;
            tray.ShowBalloonTip(5000, Title, saved
                ? "字体颜色已保存，但当前页面应用失败，请重新打开阅读页。"
                : "字体颜色保存失败，请检查本地配置目录权限。", Forms.ToolTipIcon.Warning);
            // Do not emit exception messages, which may contain user paths or page content.
            System.Diagnostics.Debug.WriteLine("Color update failed: " + error.GetType().Name);
        }
        finally
        {
            if (!closed) colorMenu.Enabled = true;
        }
    }

    private void RefreshColorMenu()
    {
        foreach (Forms.ToolStripMenuItem item in colorMenu.DropDownItems)
            item.Checked = item.Tag is ReadingColor color && color == colorPreferences.TextColor;
    }

    internal void ChangePageTurnMode(bool wheel)
    {
        try { pagingPreferences.Save(wheel); ApplyPageTurnMode(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            if (selfTest) throw;
            tray.ShowBalloonTip(5000, Title, "翻页方式保存失败，请检查本地配置目录权限。", Forms.ToolTipIcon.Warning);
        }
    }

    private void ApplyPageTurnMode()
    {
        wheelState.Reset();
        mouseCloseButton.Visibility = pagingPreferences.Wheel ? Visibility.Visible : Visibility.Collapsed;
        foreach (Forms.ToolStripMenuItem item in pagingMenu.DropDownItems)
            item.Checked = item.Tag is bool wheel && wheel == pagingPreferences.Wheel;
    }

    private bool IsReaderPage => browser.CoreWebView2 is { } core &&
        Uri.TryCreate(core.Source, UriKind.Absolute, out var uri) && uri.Scheme == "https" &&
        uri.Host == "weread.qq.com" && uri.Port == 443 && uri.UserInfo.Length == 0 &&
        uri.AbsolutePath.StartsWith("/web/reader/", StringComparison.Ordinal);

    private async void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (!pagingPreferences.Wheel || !IsReaderPage)
        { wheelState.Reset(); return; }
        if (Keyboard.Modifiers != ModifierKeys.None) { wheelState.ClearMotion(); return; }
        e.Handled = true;
        bool eligible = !closed && IsActive && IsEnabled && IsVisible;
        int? direction = wheelState.Consume(e.Delta, Environment.TickCount64 / 1000.0, eligible);
        if (direction is null || pageTurnPending) return;
        pageTurnPending = true;
        try
        {
            if (!eligible || !browser.Focus() || browser.CoreWebView2 is not { } core) return;
            bool next = direction > 0;
            string key = next ? "ArrowRight" : "ArrowLeft";
            int code = next ? 39 : 37;
            await core.CallDevToolsProtocolMethodAsync("Input.dispatchKeyEvent", JsonSerializer.Serialize(new
            { type = "rawKeyDown", key, code = key, windowsVirtualKeyCode = code }));
            if (closed) return;
            await core.CallDevToolsProtocolMethodAsync("Input.dispatchKeyEvent", JsonSerializer.Serialize(new
            { type = "keyUp", key, code = key, windowsVirtualKeyCode = code }));
        }
        catch (Exception)
        {
            if (!closed) tray.ShowBalloonTip(3000, Title, "滚轮翻页失败，请使用左右方向键重试。", Forms.ToolTipIcon.Warning);
        }
        finally { pageTurnPending = false; }
    }

    private void HideReader()
    {
        Hide();
        wheelState.Reset();
    }

    internal void ToggleVisibility()
    {
        if (IsVisible)
        {
            HideReader(); // Native removal first; never wait for JavaScript.
        }
        else Restore();
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
        if (!exiting) { e.Cancel = true; HideReader(); }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        closed = true;
        hotKey?.Dispose();
        tray.Visible = false;
        tray.ContextMenuStrip?.Dispose();
        tray.Dispose();
        appIcon.Dispose();
        browser.Dispose();
        base.OnClosed(e);
    }
}
