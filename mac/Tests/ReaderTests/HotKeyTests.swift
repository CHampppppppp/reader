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
        var press = HotKeyPressState()
        check(press.update(pressed: true), "First press triggers")
        check(!press.update(pressed: true), "Held key repeat is ignored")
        check(!press.update(pressed: false), "Release does not toggle")
        check(press.update(pressed: true), "Next press after release triggers")
        let arrow = GlobalHotKey()
        let status = arrow.register(Shortcut.choices[Shortcut.defaultIndex])
        check(status == noErr || status == OSStatus(eventHotKeyExistsErr), "Plain Command + Up Arrow is supported or already reserved")
        print(status == noErr ? "PASS: Command + Up Arrow native registration" : "SKIP: Command + Up Arrow already reserved by a running app")
        print("PASS: native shortcut conflict, retry and repeat suppression checks")
        withExtendedLifetime(candidate) {}
    }

    static func check(_ value: Bool, _ description: String) {
        guard value else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    }
}
