import AppKit
import WebKit

final class AppearanceDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSPanel!
    private var webView: WKWebView!
    private var source = ""
    private var template = ""
    private var colorIndex = 0
    private let colors = ReadingColor.allCases.map { $0.rawValue } + ["invalid-color"]
    private var tested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            template = try String(contentsOfFile: "Resources/appearance.js", encoding: .utf8)
            source = template.replacingOccurrences(of: "__READER_SETTINGS__", with: "{transparent:true,opacity:0}")
        } catch { fail("Cannot load appearance resource") }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = TransparentWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.pageZoom = ReaderPolicy.pageZoom(for: URL(string: "https://weread.qq.com/web/reader/local-fixture"))
        webView.navigationDelegate = self
        window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = webView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.orderFrontRegardless()
        // Local fixture with the official reader's classes, no account or network resources.
        webView.loadHTMLString("""
        <html><head><style>body{margin:0;background:white} .readerChapterContent{position:relative;height:200px;display:flow-root}
        .renderTargetContent p{line-height:40px;margin-bottom:20px} #outside{color:rgb(20,40,60);position:absolute;top:180px} #purchase{position:absolute;top:205px} #goldCanvas{position:absolute;top:70px;left:10px}</style></head>
        <body><div class="wr_horizontalReader"><div class="readerChapterContent">
        <div class="renderTargetContent"><p id="text" style="color:black;font-size:20px">Golden reading text</p><p>Second paragraph</p></div>
        <div class="wr_canvasContainer"><canvas id="goldCanvas" width="80" height="40"></canvas></div>
        <div class="wr_canvasContainer"><canvas id="glyphCanvas" width="120" height="60" style="position:absolute;left:10px;top:235px"></canvas></div>
        <canvas id="glyphReference" width="120" height="60" style="position:absolute;left:170px;top:235px"></canvas>
        <canvas id="illustration" width="20" height="20" style="position:absolute;left:150px;top:80px"></canvas>
        <div style="position:absolute;left:180px;top:80px;width:10px;height:10px;background:red"></div>
        <div id="reference" style="position:absolute;left:100px;top:80px;width:10px;height:10px;background:#D4AF37"></div>
        <button class="renderTarget_pager_button">上一页</button><button class="renderTarget_pager_button renderTarget_pager_button_right">下一页</button>
        </div><div class="readerTopBar">Reader header</div></div><div id="outside">Unchanged surrounding UI</div>
        <button class="readerFooter_button" title="下一页">下一页</button>
        <button id="purchase" class="readerFooter_button blue">购买</button>
        <script>
        // The reader measures text while loading and reuses those coordinates when turning pages.
        window.firstLayout = {height: getComputedStyle(document.querySelector('#text')).lineHeight,
          margin: getComputedStyle(document.querySelector('#text')).marginBottom};
        const ctx=document.querySelector('canvas').getContext('2d');ctx.fillStyle='black';ctx.fillRect(10,10,10,10);
        for (const id of ['glyphCanvas','glyphReference']) {
          const glyph=document.getElementById(id).getContext('2d');
          glyph.font='500 22px "PingFang SC"';glyph.fillText('清晰阅读 Aa',4,30);
          glyph.globalAlpha=0.25;glyph.fillRect(100,40,10,10);
        }
        const picture=document.querySelector('#illustration').getContext('2d');picture.fillStyle='red';picture.fillRect(0,0,20,20);
        window.turns=0;document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')window.turns++});</script></body></html>
        """, baseURL: URL(string: "https://weread.qq.com/web/reader/local-fixture"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { self.fail("Appearance fixture timed out") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !tested else { return }; tested = true
        // Reinjection happens after navigation and settings changes in the app.
        webView.evaluateJavaScript(source) { _, error in
            guard error == nil else { self.fail("Script injection failed") }
            self.verifyDOM()
        }
    }

    private func verifyDOM() {
        webView.evaluateJavaScript("""
        (()=>{
          document.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));
          const canvas=document.querySelector('#goldCanvas'), r=canvas.getBoundingClientRect(), ref=document.querySelector('#reference').getBoundingClientRect(), picture=document.querySelector('#illustration').getBoundingClientRect();
          const glyph=document.querySelector('#glyphCanvas').getBoundingClientRect(), original=document.querySelector('#glyphReference').getBoundingClientRect();
          return {gold:getComputedStyle(document.querySelector('#text')).color===getComputedStyle(document.querySelector('#reference')).backgroundColor,
            hidden:[...document.querySelectorAll('.renderTarget_pager_button,[title="下一页"]')].every(e=>getComputedStyle(e).display==='none'),
            outside:getComputedStyle(document.querySelector('#outside')).color==='rgb(20, 40, 60)',
            purchase:getComputedStyle(document.querySelector('#purchase')).display!=='none',
            unique:document.querySelectorAll('#qingdu-appearance').length===1&&document.querySelectorAll('#qingdu-text-filters').length===1,
            keys:window.turns===\(colorIndex + 1),
            stableLayout:window.firstLayout.height===getComputedStyle(document.querySelector('#text')).lineHeight&&window.firstLayout.margin===getComputedStyle(document.querySelector('#text')).marginBottom,
            density:parseFloat(getComputedStyle(document.querySelector('#text')).lineHeight)===31&&parseFloat(getComputedStyle(document.querySelector('#text')).marginBottom)===12,
            zoom:innerWidth===400,
            crisp:getComputedStyle(document.querySelector('#text')).textShadow==='none',
            transparent:[document.body,document.querySelector('.readerChapterContent'),document.querySelector('.readerTopBar')].every(e=>getComputedStyle(e).backgroundColor.endsWith(', 0)')),
            x:r.left+15, y:r.top+15, refX:ref.left+5, refY:ref.top+5, picX:picture.left+5, picY:picture.top+5,
            glyphX:glyph.left, glyphY:glyph.top, originalX:original.left, originalY:original.top};
        })()
        """) { result, error in
            guard error == nil, let result = result as? [String: Any] else { self.fail("Cannot inspect fixture") }
            for key in ["gold", "hidden", "outside", "purchase", "unique", "keys", "stableLayout", "density", "zoom", "crisp", "transparent"] {
                guard result[key] as? Bool == true else { self.fail("Appearance rule failed: \(key)") }
            }
            guard let x = result["x"] as? Double, let y = result["y"] as? Double,
                  let refX = result["refX"] as? Double, let refY = result["refY"] as? Double,
                  let picX = result["picX"] as? Double, let picY = result["picY"] as? Double,
                  let glyphX = result["glyphX"] as? Double, let glyphY = result["glyphY"] as? Double,
                  let originalX = result["originalX"] as? Double, let originalY = result["originalY"] as? Double else { self.fail("Canvas position missing") }
            self.verifyCanvas(x: x, y: y, refX: refX, refY: refY, picX: picX, picY: picY,
                glyph: NSPoint(x: glyphX, y: glyphY), original: NSPoint(x: originalX, y: originalY))
        }
    }

    private func verifyCanvas(x: Double, y: Double, refX: Double, refY: Double, picX: Double, picY: Double,
                              glyph: NSPoint, original: NSPoint) {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        webView.takeSnapshot(with: configuration) { image, error in
            guard error == nil, let image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { self.fail("Cannot snapshot fixture") }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let emptyPixel = bitmap.colorAt(x: bitmap.pixelsWide - 5, y: bitmap.pixelsHigh - 5),
                  emptyPixel.alphaComponent < 0.01 else { self.fail("WebKit background is not transparent") }
            let scale = Double(bitmap.pixelsWide) / self.webView.bounds.width * self.webView.pageZoom
            self.verifyGlyphAlpha(bitmap, scale: scale, glyph: glyph, original: original)
            guard let color = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { self.fail("Cannot inspect canvas color") }
            // Compare with a CSS gold swatch from the same snapshot to account for display color profiles.
            guard let reference = bitmap.colorAt(x: Int(refX * scale), y: Int(refY * scale))?.usingColorSpace(.sRGB) else { self.fail("Cannot inspect reference color") }
            guard abs(color.redComponent - reference.redComponent) < 0.02,
                  abs(color.greenComponent - reference.greenComponent) < 0.02,
                  abs(color.blueComponent - reference.blueComponent) < 0.02 else {
                self.fail("Canvas did not match selected color: \(color)")
            }
            guard let picture = bitmap.colorAt(x: Int(picX * scale), y: Int(picY * scale))?.usingColorSpace(.sRGB) else {
                self.fail("Cannot inspect illustration")
            }
            // Compare against a CSS red swatch in the same snapshot for display color profiles.
            guard let pictureReference = bitmap.colorAt(x: Int((picX + 30) * scale), y: Int(picY * scale))?.usingColorSpace(.sRGB),
                  abs(picture.redComponent - pictureReference.redComponent) < 0.02,
                  abs(picture.greenComponent - pictureReference.greenComponent) < 0.02,
                  abs(picture.blueComponent - pictureReference.blueComponent) < 0.02,
                  picture.alphaComponent > 0.99 else { self.fail("Illustration was recolored") }
            print("PASS: DOM and canvas color \(self.colors[self.colorIndex]), unchanged glyph alpha, stable layout, transparent pixels and unchanged illustrations")
            self.colorIndex += 1
            guard self.colorIndex < self.colors.count else {
                fflush(stdout)
                NSApp.terminate(nil)
                return
            }
            let nextColor = self.colors[self.colorIndex]
            let expected = ReadingColor(rawValue: nextColor)?.rawValue ?? ReadingColor.gold.rawValue
            let script = self.template.replacingOccurrences(of: "__READER_SETTINGS__",
                with: "{transparent:true,opacity:0,textColor:'\(nextColor)'}")
                + ";document.querySelector('#reference').style.backgroundColor='\(expected)';"
            self.webView.evaluateJavaScript(script) { _, error in
                guard error == nil else { self.fail("Color change script failed") }
                self.verifyDOM()
            }
        }
    }

    private func verifyGlyphAlpha(_ bitmap: NSBitmapImageRep, scale: Double, glyph: NSPoint, original: NSPoint) {
        let glyphX = Int((glyph.x * scale).rounded()), glyphY = Int((glyph.y * scale).rounded())
        let originalX = Int((original.x * scale).rounded()), originalY = Int((original.y * scale).rounded())
        let width = Int(120 * scale), height = Int(60 * scale)
        guard glyphX >= 0, glyphY >= 0, originalX >= 0, originalY >= 0,
              glyphX + width <= bitmap.pixelsWide, originalX + width <= bitmap.pixelsWide,
              glyphY + height <= bitmap.pixelsHigh, originalY + height <= bitmap.pixelsHigh else {
            fail("Glyph fixture is clipped")
        }
        // Compare full glyph masks, including antialiased edges and a 25% alpha swatch.
        var inkPixels = 0, edgePixels = 0
        for dy in 0..<height {
            for dx in 0..<width {
                guard let actual = bitmap.colorAt(x: glyphX + dx, y: glyphY + dy),
                      let reference = bitmap.colorAt(x: originalX + dx, y: originalY + dy) else {
                    fail("Cannot inspect glyph alpha")
                }
                guard abs(actual.alphaComponent - reference.alphaComponent) < 0.02 else {
                    fail("Canvas coloring thickened glyphs or changed edge alpha")
                }
                if reference.alphaComponent > 0.01 { inkPixels += 1 }
                if reference.alphaComponent > 0.01 && reference.alphaComponent < 0.99 { edgePixels += 1 }
            }
        }
        guard inkPixels > 100, edgePixels > 20 else { fail("Glyph comparison fixture is empty") }
    }

    private func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct AppearanceTests {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppearanceDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
