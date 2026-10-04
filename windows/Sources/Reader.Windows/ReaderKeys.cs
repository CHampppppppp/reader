using System.Windows.Input;

namespace Qingdu.Windows;

internal static class ReaderKeys
{
    internal const uint VisibilityKey = 0x26; // VK_UP
    internal const uint VisibilityModifiers = 0x4002; // MOD_NOREPEAT | MOD_CONTROL

    internal static bool HidesReader(Key key, ModifierKeys modifiers, bool isActive) =>
        isActive && key == Key.Up && modifiers == ModifierKeys.None;

    internal static bool ReturnsToBooks(Key key, ModifierKeys modifiers, bool isActive) =>
        isActive && key == Key.Down && modifiers == ModifierKeys.None;
}
