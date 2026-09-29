using System;
using System.Windows;

namespace Qingdu.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool selfTest = Array.IndexOf(args, "--self-test") >= 0;
        bool website = !selfTest && Array.IndexOf(args, "--website") >= 0;
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        var window = new ReadingWindow(website, selfTest);
        app.MainWindow = window;
        app.Startup += (_, _) => window.Start();
        return app.Run();
    }
}
