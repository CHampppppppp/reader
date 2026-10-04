import Foundation
import Carbon

struct Shortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static let choices = [
        Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space"),
        Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥ Space"),
        Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey), label: "⇧⌘ R"),
        Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt32(cmdKey), label: "⌘0"),
        Shortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(cmdKey), label: "⌘↑")
    ]
    static let defaultIndex = 4
}

enum ReaderPolicy {
    static let home = URL(string: "https://weread.qq.com/")!

    static func isWeRead(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "weread.qq.com"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func resumableURL(_ value: String?) -> URL {
        guard let value, let url = URL(string: value), isWeRead(url),
              url.path.hasPrefix("/web/reader/"), url.query == nil, url.fragment == nil else { return home }
        return url
    }

    static func pageZoom(for url: URL?) -> Double {
        guard let url, isWeRead(url), url.path.hasPrefix("/web/reader/") else { return 1 }
        return 1
    }

    static func bounded(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

enum ReadingColor: String, CaseIterable {
    case gold = "#D4AF37", white = "#FFFFFF", black = "#202124"
    case gray = "#A0A0A0", green = "#7CBF88", blue = "#82B1FF"

    var label: String {
        switch self {
        case .gold: return "金色"
        case .white: return "白色"
        case .black: return "黑色"
        case .gray: return "灰色"
        case .green: return "护眼绿"
        case .blue: return "蓝色"
        }
    }
}

enum PageTurnMode: String, CaseIterable {
    case keyboard, wheel
    var label: String { self == .keyboard ? "方向键翻页" : "鼠标滚轮翻页" }
}

final class Preferences {
    private let store: UserDefaults
    init(store: UserDefaults = .standard) {
        self.store = store
        if !store.bool(forKey: "clearBackgroundApplied") {
            store.set(true, forKey: "transparent")
            store.set(0.0, forKey: "backgroundOpacity")
            store.set(true, forKey: "clearBackgroundApplied")
        }
    }
    var textColor: ReadingColor {
        get { ReadingColor(rawValue: store.string(forKey: "textColor") ?? "") ?? .gold }
        set { store.set(newValue.rawValue, forKey: "textColor") }
    }
    var pageTurnMode: PageTurnMode {
        get { PageTurnMode(rawValue: store.string(forKey: "pageTurnMode") ?? "") ?? .keyboard }
        set { store.set(newValue.rawValue, forKey: "pageTurnMode") }
    }
    var transparent: Bool {
        get { store.object(forKey: "transparent") as? Bool ?? true }
        set { store.set(newValue, forKey: "transparent") }
    }
    var backgroundOpacity: Double {
        get { ReaderPolicy.bounded(store.object(forKey: "backgroundOpacity") as? Double ?? 0, fallback: 0, range: 0...1) }
        set { store.set(ReaderPolicy.bounded(newValue, fallback: 0, range: 0...1), forKey: "backgroundOpacity") }
    }
    var windowOpacity: Double {
        get { ReaderPolicy.bounded(store.object(forKey: "windowOpacity") as? Double ?? 1, fallback: 1, range: 0.25...1) }
        set { store.set(ReaderPolicy.bounded(newValue, fallback: 1, range: 0.25...1), forKey: "windowOpacity") }
    }
    var shortcutIndex: Int {
        // A new preference version applies the requested Command + Up Arrow to existing installs once.
        // Subsequent choices persist without resetting on every launch.
        get {
            let n = store.object(forKey: "shortcutIndex.v4") as? Int ?? Shortcut.defaultIndex
            return Shortcut.choices.indices.contains(n) ? n : Shortcut.defaultIndex
        }
        set { store.set(newValue, forKey: "shortcutIndex.v4") }
    }
    var hideMenuIcon: Bool {
        get { store.bool(forKey: "hideMenuIcon") }
        set { store.set(newValue, forKey: "hideMenuIcon") }
    }
    var lastURL: URL { ReaderPolicy.resumableURL(store.string(forKey: "lastReaderURL")) }
    func remember(_ url: URL) {
        guard ReaderPolicy.isWeRead(url), url.path.hasPrefix("/web/reader/") else { return }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.query = nil
        parts?.fragment = nil
        store.set(parts?.url?.absoluteString, forKey: "lastReaderURL")
    }
}
