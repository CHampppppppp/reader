import AppKit
import WebKit

final class SmokeDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSPanel!
    private var webView: WKWebView!
    private var didStart = false
    private var webCompleted = false
    private var hiddenDuringWork = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Isolated, offscreen fixture: no website, account, cookies, or user preferences.
        window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 400),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "busyStarted")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFrontRegardless()
        webView.loadHTMLString("<html><body>Isolated window lifecycle test</body></html>", baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.fail("Timed out") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didStart else { return }
        didStart = true
        // Keep the WebContent process busy for 2 seconds. The native hide must not wait.
        webView.evaluateJavaScript("window.webkit.messageHandlers.busyStarted.postMessage('started'); const start = performance.now(); while (performance.now() - start < 2000) {} ; true") { result, error in
            self.webCompleted = true
            guard error == nil, result as? Bool == true, self.hiddenDuringWork else {
                self.fail("Web work or concurrent hide did not complete as expected")
            }
            self.window.orderFrontRegardless()
            guard self.window.isVisible else { self.fail("Window did not restore") }
            WindowVisibility.hide(self.window)
            guard !self.window.isVisible else { self.fail("Restored window did not hide") }
            print("PASS: restore and repeated hide; no WebKit wait on native hide path")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "busyStarted", message.body as? String == "started" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !self.webCompleted, self.window.isVisible else { self.fail("Invalid busy-page fixture") }
            let start = DispatchTime.now().uptimeNanoseconds
            WindowVisibility.hide(self.window)
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            guard !self.window.isVisible else { self.fail("Window remained visible") }
            guard milliseconds < 500 else { self.fail("Native hide exceeded 500 ms while page was busy") }
            self.hiddenDuringWork = true
            print(String(format: "PASS: native hide while JavaScript busy: %.2f ms", milliseconds))
        }
    }

    private func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct WindowSmokeTests {
    static func main() {
        let application = NSApplication.shared
        let delegate = SmokeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
