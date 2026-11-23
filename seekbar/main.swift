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
let sliderID = NSTouchBarItem.Identifier("seek.slider")
let closeID = NSTouchBarItem.Identifier("seek.close")

final class Controller: NSObject, NSTouchBarDelegate {
    let bar = NSTouchBar()
    let slider = NSSliderTouchBarItem(identifier: sliderID)
    var lastTouch = Date.distantPast
    var lastSeek = Date.distantPast
    var lastActivity = Date()
    var polling = false

    override init() {
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = [sliderID, closeID]
        slider.slider.minValue = 0; slider.slider.maxValue = 1
        slider.minimumSliderWidth = 520; slider.maximumSliderWidth = 760
        slider.target = self; slider.action = #selector(moved)
        slider.label = "…"
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if id == sliderID { return slider }
        if id == closeID {
            let i = NSCustomTouchBarItem(identifier: id)
            i.view = NSButton(title: "✕", target: self, action: #selector(close))
            return i
        }
        return nil
    }
    @objc func close() { dismiss(); NSApp.terminate(nil) }
    @objc func moved() {
        lastTouch = Date(); lastActivity = Date()
        let f = slider.slider.doubleValue
        if Date().timeIntervalSince(lastSeek) > 0.15 {
            lastSeek = Date()
            DispatchQueue.global().async { _ = osa(tabScript(seekJS(f))) }
        }
        // final position on touch-up
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(finalSeek), object: nil)
        perform(#selector(finalSeek), with: nil, afterDelay: 0.25)
    }
    @objc func finalSeek() {
        let f = slider.slider.doubleValue
        DispatchQueue.global().async { _ = osa(tabScript(seekJS(f))) }
    }
    func fmt(_ s: Double) -> String { let i = Int(s); return String(format: "%d:%02d", i/60, i%60) }
    func poll() {
        guard !polling, Date().timeIntervalSince(lastTouch) > 1.5 else { return }
        polling = true
        DispatchQueue.global().async {
            let r = osa(tabScript(statusJS)); 
            DispatchQueue.main.async {
                self.polling = false
                let p = r.components(separatedBy: "|")
                guard p.count == 3, let c = Double(p[1]), let d = Double(p[2]), d > 0 else { return }
                self.slider.slider.doubleValue = c / d
                var t = p[0]; if t.count > 28 { t = String(t.prefix(27)) + "…" }
                self.slider.label = "\(t)  \(self.fmt(c)) / \(self.fmt(d))"
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
