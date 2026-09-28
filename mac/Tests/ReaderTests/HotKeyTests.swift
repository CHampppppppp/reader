import AppKit
import Carbon

@main
struct HotKeyTests {
    static func main() {
        _ = NSApplication.shared
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let first = Shortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers, label: "Test F19")
        let second = Shortcut(keyCode: UInt32(kVK_F18), modifiers: modifiers, label: "Test F18")
        var owner: GlobalHotKey? = GlobalHotKey()
        let candidate = GlobalHotKey()
        check(owner!.register(first) == noErr, "Reserve isolated test shortcut")
        check(candidate.register(first) != noErr, "Exclusive conflict is reported")
        check(!candidate.isRegistered, "Failed initial registration stays unavailable")
        check(candidate.register(second) == noErr, "Alternative shortcut can register")
        check(candidate.register(first) != noErr, "Replacement conflict is reported")
        check(candidate.isRegistered, "Working registration survives replacement failure")
        owner = nil
        check(candidate.register(first) == noErr, "Same shortcut can retry after conflict clears")
        print("PASS: 7 native shortcut registration checks")
        withExtendedLifetime(candidate) {}
    }

    static func check(_ value: Bool, _ description: String) {
        guard value else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    }
}
