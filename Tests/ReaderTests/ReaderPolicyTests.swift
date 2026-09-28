import Foundation

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
        check(Shortcut.choices.allSatisfy { $0.modifiers != 0 }, "All shortcuts include modifiers")
        check(ReaderPolicy.pageZoom(for: URL(string: reading)) == 1, "Reader uses full-size scale")
        check(ReaderPolicy.pageZoom(for: ReaderPolicy.home) == 1, "Bookstore keeps normal scale")
        check(ReaderPolicy.pageZoom(for: URL(string: "https://weread.qq.com.evil.test/web/reader/123")) == 1, "Other hosts keep normal scale")
        check(ReaderPolicy.pageZoom(for: nil) == 1, "Empty page keeps normal scale")
        print("PASS: \(checks) policy checks")
    }
}
