import AppKit

// --- osascript helpers (talks to Brave/Chrome YouTube tab) ---
func osa(_ script: String) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
func tabScript(_ js: String) -> String {
    let e = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return """
    on probe(appName)
      if application appName is not running then return ""
      using terms from application "Google Chrome"
        tell application appName
          repeat with w in windows
            repeat with t in tabs of w
              if URL of t contains "youtube.com" then
                set r to execute t javascript "\(e)"
                if r is not "" and r is not missing value then return r
              end if
            end repeat
          end repeat
        end tell
      end using terms from
      return ""
    end probe
    set r to my probe("Brave Browser")
    if r is "" then set r to my probe("Google Chrome")
    return r
    """
}
let statusJS = "(function(){var v=document.querySelector('video');if(!v||v.paused)return '';var m=navigator.mediaSession&&navigator.mediaSession.metadata;var t=m&&m.title?m.title:document.title;var a=m&&m.artist?' – '+m.artist:'';return t+a+'|'+v.currentTime+'|'+v.duration})()"
func seekJS(_ f: Double) -> String { "(function(){var v=document.querySelector('video');if(!v||v.paused)return '';v.currentTime=\(f)*v.duration;return 'ok'})()" }

// --- Touch Bar ---
let titleID = NSTouchBarItem.Identifier("seek.title")
let linesID = NSTouchBarItem.Identifier("seek.lines")
let timeID = NSTouchBarItem.Identifier("seek.time")
let closeID = NSTouchBarItem.Identifier("seek.close")

/// Row of vertical lines: blue = played, bright white = now, faint white = still to play. Touch or drag to seek.
final class LinesView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var onSeek: ((Double) -> Void)?
    var onEnd: (() -> Void)?
    override var allowedTouchTypes: NSTouch.TouchTypeMask { get { .direct } set {} }
    override var intrinsicContentSize: NSSize { NSSize(width: 640, height: 30) }
    override func draw(_ dirtyRect: NSRect) {
        let n = max(20, Int(bounds.width / 6.5)), w = bounds.width / CGFloat(n)
        let cur = min(n - 1, max(0, Int((fraction * Double(n - 1)).rounded())))
        for i in 0..<n {
            let x = CGFloat(i) * w + w / 2
            let isCur = i == cur
            let h: CGFloat = isCur ? 28 : 16
            let lw: CGFloat = isCur ? 5 : (i < cur ? 3 : 2)
            let path = NSBezierPath(roundedRect: NSRect(x: x - lw / 2, y: (bounds.height - h) / 2, width: lw, height: h), xRadius: lw / 2, yRadius: lw / 2)
            (isCur ? NSColor.white : i < cur ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.3)).setFill()
            path.fill()
        }
    }
    func seek(_ e: NSEvent) {
        guard let t = e.touches(matching: .touching, in: self).first ?? e.touches(matching: .any, in: self).first else { return }
        let f = Double(min(1, max(0, t.location(in: self).x / bounds.width)))
        fraction = f; onSeek?(f)
    }
    override func touchesBegan(with e: NSEvent) { seek(e) }
    override func touchesMoved(with e: NSEvent) { seek(e) }
    override func touchesEnded(with e: NSEvent) { onEnd?() }
    override func touchesCancelled(with e: NSEvent) { onEnd?() }
}

final class Controller: NSObject, NSTouchBarDelegate {
    let bar = NSTouchBar()
    let lines = LinesView()
    let titleField = NSTextField(labelWithString: "…")
    let timeField = NSTextField(labelWithString: "")
    var lastTouch = Date.distantPast
    var lastSeek = Date.distantPast
    var lastActivity = Date()
    var polling = false

    override init() {
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = [titleID, linesID, timeID, closeID]
        titleField.font = .systemFont(ofSize: 12, weight: .semibold); titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(equalToConstant: 170).isActive = true
        timeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); timeField.textColor = .secondaryLabelColor
        lines.onSeek = { [weak self] f in self?.moved(f) }
        lines.onEnd = { [weak self] in self?.finalSeek() }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let i = NSCustomTouchBarItem(identifier: id)
        switch id {
        case titleID: i.view = titleField
        case linesID: i.view = lines
        case timeID: i.view = timeField
        case closeID: i.view = NSButton(title: "✕", target: self, action: #selector(close))
        default: return nil
        }
        return i
    }
    @objc func close() { dismiss(); NSApp.terminate(nil) }
    func moved(_ f: Double) {
        lastTouch = Date(); lastActivity = Date()
        if Date().timeIntervalSince(lastSeek) > 0.15 {
            lastSeek = Date()
            DispatchQueue.global().async { _ = osa(tabScript(seekJS(f))) }
        }
    }
    func finalSeek() {
        lastTouch = Date(); lastActivity = Date()
        let f = lines.fraction
        DispatchQueue.global().async { _ = osa(tabScript(seekJS(f))) }
    }
    func fmt(_ s: Double) -> String { let i = Int(s); return String(format: "%d:%02d", i/60, i%60) }
    func poll() {
        guard !polling, Date().timeIntervalSince(lastTouch) > 1.5 else { return }
        polling = true
        DispatchQueue.global().async {
            let r = osa(tabScript(statusJS))
            DispatchQueue.main.async {
                self.polling = false
                let p = r.components(separatedBy: "|")
                guard p.count >= 3, let c = Double(p[p.count - 2]), let d = Double(p[p.count - 1]), d > 0 else { return }
                self.lines.fraction = c / d
                self.titleField.stringValue = p.dropLast(2).joined(separator: "|")
                self.timeField.stringValue = "\(self.fmt(c)) / \(self.fmt(d))"
            }
        }
    }
    func present() {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
        if let m = class_getClassMethod(NSTouchBar.self, sel) {
            unsafeBitCast(method_getImplementation(m), to: Fn.self)(NSTouchBar.self, sel, bar, 1, nil)
        }
    }
    func dismiss() {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        if let m = class_getClassMethod(NSTouchBar.self, sel) {
            unsafeBitCast(method_getImplementation(m), to: Fn.self)(NSTouchBar.self, sel, bar)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let c = Controller()
c.present()
c.poll()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    c.poll()
    if Date().timeIntervalSince(c.lastActivity) > 8 { c.dismiss(); NSApp.terminate(nil) }
}
app.run()
