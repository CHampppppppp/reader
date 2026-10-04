import Foundation
import Carbon

@main
struct ReaderPolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else {
                fputs("FAIL: \(name)\n", stderr)
                exit(1)
            }
            checks += 1
        }
        let reading = "https://weread.qq.com/web/reader/123"
        check(ReaderPolicy.resumableURL(reading).absoluteString == reading, "Restore official reader")
        let invalid: [String?] = [nil, "bad", "https://weread.qq.com.evil.test/web/reader/123",
            "http://weread.qq.com/web/reader/123", "https://weread.qq.com/web/reader/123?token=secret",
            "https://weread.qq.com/web/reader/123#secret", "https://weread.qq.com/login",
            "https://alice:password@weread.qq.com/web/reader/123", "https://weread.qq.com:8443/web/reader/123"]
        for input in invalid {
            check(ReaderPolicy.resumableURL(input) == ReaderPolicy.home, "Reject non-reader or credential URL")
        }
        check(ReaderPolicy.bounded(0, fallback: 1, range: 0.25...1) == 0.25, "Keep window visible")
        check(ReaderPolicy.bounded(2, fallback: 1, range: 0.25...1) == 1, "Clamp upper limit")
        check(ReaderPolicy.bounded(.nan, fallback: 1, range: 0.25...1) == 1, "Reject NaN")
        check(ReaderPolicy.bounded(0.6, fallback: 1, range: 0.25...1) == 0.6, "Retain valid opacity")
        check(Set(Shortcut.choices.map { "\($0.keyCode):\($0.modifiers)" }).count == Shortcut.choices.count,
              "Distinct shortcuts")
        check(Shortcut.choices[Shortcut.defaultIndex].keyCode == UInt32(kVK_UpArrow)
              && Shortcut.choices[Shortcut.defaultIndex].modifiers == UInt32(cmdKey), "Default is Command + Up Arrow")
        check(Shortcut.choices.allSatisfy { $0.modifiers != 0 }, "Global shortcuts always require modifiers")
        check(ReaderPolicy.pageZoom(for: URL(string: reading)) == 1, "Reader uses full-size scale")
        check(ReaderPolicy.pageZoom(for: ReaderPolicy.home) == 1, "Bookstore keeps normal scale")
        check(ReaderPolicy.pageZoom(for: URL(string: "https://weread.qq.com.evil.test/web/reader/123")) == 1, "Other hosts keep normal scale")
        check(ReaderPolicy.pageZoom(for: nil) == 1, "Empty page keeps normal scale")
        let suite = "reader-color-tests-\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: suite) else { fatalError("Cannot create isolated preferences") }
        let preferences = Preferences(store: store)
        store.set(3, forKey: "shortcutIndex.v3")
        check(preferences.shortcutIndex == Shortcut.defaultIndex, "Old shortcut migrates to Command + Up Arrow")
        preferences.shortcutIndex = 0
        check(Preferences(store: store).shortcutIndex == 0, "Later shortcut choice survives restart")
        check(preferences.textColor == .gold, "Existing preferences default to gold")
        for color in ReadingColor.allCases {
            preferences.textColor = color
            check(Preferences(store: UserDefaults(suiteName: suite)!).textColor == color, "Color survives preference reload")
        }
        store.set("invalid-color", forKey: "textColor")
        check(preferences.textColor == .gold, "Invalid color falls back to gold")
        check(preferences.pageTurnMode == .keyboard, "Keyboard is default paging mode")
        preferences.pageTurnMode = .wheel
        check(Preferences(store: store).pageTurnMode == .wheel, "Paging mode persists")
        store.set("invalid", forKey: "pageTurnMode")
        check(preferences.pageTurnMode == .keyboard, "Invalid paging mode falls back")
        print("PASS: \(checks) policy checks")
    }
}
