using System;
using System.IO;

namespace Qingdu.Windows;

internal sealed class PagingPreferences
{
    private readonly string path;
    internal bool Wheel { get; private set; }
    internal bool LoadFailed { get; }
    internal PagingPreferences(string path)
    {
        this.path = path;
        try { Wheel = File.ReadAllText(path).Trim() == "wheel"; }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { LoadFailed = true; }
    }
    internal void Save(bool wheel)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string pending = path + "." + Guid.NewGuid().ToString("N") + ".pending";
        File.WriteAllText(pending, wheel ? "wheel" : "keyboard");
        File.Move(pending, path, overwrite: true);
        Wheel = wheel;
    }
}

internal sealed class WheelPagingState
{
    private double accumulated;
    private double lastEvent = double.NegativeInfinity;
    private double lastTurn = double.NegativeInfinity;
    internal void Reset() { accumulated = 0; lastEvent = lastTurn = double.NegativeInfinity; }
    internal void ClearMotion() { accumulated = 0; lastEvent = double.NegativeInfinity; }
    internal int? Consume(int delta, double time, bool eligible)
    {
        if (!eligible || !double.IsFinite(time)) { Reset(); return null; }
        if (delta == 0) return null;
        if (time - lastEvent > 0.35 || accumulated * delta < 0) accumulated = 0;
        lastEvent = time;
        if (time - lastTurn < 0.3) { accumulated = 0; return null; }
        accumulated += delta;
        if (Math.Abs(accumulated) < 120) return null;
        int direction = accumulated < 0 ? 1 : -1;
        accumulated = 0;
        lastTurn = time;
        return direction;
    }
}
