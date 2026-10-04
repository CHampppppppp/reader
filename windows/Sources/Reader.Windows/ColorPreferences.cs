using System;
using System.Collections.Generic;
using System.IO;

namespace Qingdu.Windows;

internal sealed record ReadingColor(string Label, string Hex)
{
    internal static IReadOnlyList<ReadingColor> Choices { get; } = Array.AsReadOnly(new[]
    {
        new ReadingColor("金色", "#D4AF37"), new ReadingColor("白色", "#FFFFFF"),
        new ReadingColor("黑色", "#202124"), new ReadingColor("灰色", "#A0A0A0"),
        new ReadingColor("护眼绿", "#7CBF88"), new ReadingColor("蓝色", "#82B1FF")
    });

    internal static ReadingColor Resolve(string? hex)
    {
        foreach (var color in Choices)
            if (color.Hex == hex) return color;
        return Choices[0];
    }
}

internal sealed class ColorPreferences
{
    private readonly string path;
    internal ReadingColor TextColor { get; private set; } = ReadingColor.Choices[0];
    internal bool LoadFailed { get; }

    internal ColorPreferences(string path)
    {
        this.path = path;
        try { TextColor = ReadingColor.Resolve(File.ReadAllText(path).Trim()); }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            LoadFailed = true;
        }
    }

    internal void Save(ReadingColor color)
    {
        color = ReadingColor.Resolve(color.Hex);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string pendingPath = path + "." + Guid.NewGuid().ToString("N") + ".pending";
        File.WriteAllText(pendingPath, color.Hex);
        File.Move(pendingPath, path, overwrite: true);
        TextColor = color;
    }
}
