import AppKit

enum WindowVisibility {
    // This path must never call WebKit, evaluate JavaScript, perform I/O, or wait for sync.
    static func hide(_ window: NSWindow) {
        window.orderOut(nil)
        for other in NSApp.windows where other !== window && other.isVisible {
            other.orderOut(nil)
        }
    }
}
