import AppKit
import ApplicationServices
import AVFoundation

// ---------- actions ----------
func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
    log("key \(code) flags=\(flags.rawValue) trusted=\(AXIsProcessTrusted())")
    for down in [true, false] {
        if let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) { e.flags = flags; e.post(tap: .cghidEventTap) }
    }
}
func sh(_ path: String, _ args: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let o = Pipe(); p.standardOutput = o; p.standardError = Pipe(); try? p.run(); p.waitUntilExit()
    return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
func focusedWindow() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var w: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &w) == .success else { return nil }
    return (w as! AXUIElement)
}
func axPoint(_ w: AXUIElement, _ attr: String) -> CGPoint {
    var v: CFTypeRef?; var p = CGPoint.zero
    if AXUIElementCopyAttributeValue(w, attr as CFString, &v) == .success { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    return p
}
func axSize(_ w: AXUIElement) -> CGSize {
    var v: CFTypeRef?; var s = CGSize.zero
    if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &v) == .success { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return s
}
func place(_ w: AXUIElement, in screen: NSScreen, _ f: (CGFloat, CGFloat, CGFloat, CGFloat)) {
    let ph = NSScreen.screens[0].frame.height, vf = screen.visibleFrame
    var pos = CGPoint(x: vf.minX + f.0 * vf.width, y: ph - vf.maxY + f.1 * vf.height)
    var size = CGSize(width: f.2 * vf.width, height: f.3 * vf.height)
    func setSize() { if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) } }
    func setPos() { if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) } }
    setSize(); setPos(); setSize()
}
func currentScreen(_ w: AXUIElement) -> NSScreen {
    let ph = NSScreen.screens[0].frame.height
    let p = axPoint(w, kAXPositionAttribute as String), s = axSize(w)
    let c = CGPoint(x: p.x + s.width / 2, y: ph - (p.y + s.height / 2))
    return NSScreen.screens.first { $0.frame.contains(c) } ?? NSScreen.main!
}
func tile(_ f: (CGFloat, CGFloat, CGFloat, CGFloat)) { if let w = focusedWindow() { place(w, in: currentScreen(w), f) } }
func nextDisplay() {
    guard let w = focusedWindow(), NSScreen.screens.count > 1 else { return }
    let cur = currentScreen(w); let i = NSScreen.screens.firstIndex(of: cur) ?? 0
    place(w, in: NSScreen.screens[(i + 1) % NSScreen.screens.count], (0, 0, 1, 1))
}

func shotPath() -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return NSHomeDirectory() + "/Desktop/Screenshot " + f.string(from: Date()) + ".png"
}
// ---------- bar definitions ----------
struct B { let id: String; let icon: String; let title: String; let run: () -> Void }
let cmd: CGEventFlags = .maskCommand, cmdShift: CGEventFlags = [.maskCommand, .maskShift]
let bars: [String: [B]] = [
 "control": [],
 "command": [
  B(id: "area", icon: "rectangle.dashed", title: "", run: { _ = sh("/usr/sbin/screencapture", ["-ic"]) }),
  B(id: "screen", icon: "display", title: "", run: { _ = sh("/usr/sbin/screencapture", ["-c"]) }),
  B(id: "win", icon: "macwindow", title: "", run: { _ = sh("/usr/sbin/screencapture", ["-icw"]) }),
  B(id: "rec", icon: "record.circle", title: "", run: { _ = sh("/usr/bin/open", ["-a", "Screenshot"]) })],
 "option": [
  B(id: "tl", icon: "rectangle.inset.topleft.filled", title: "", run: { tile((0, 0, 0.5, 0.5)) }),
  B(id: "tr", icon: "rectangle.inset.topright.filled", title: "", run: { tile((0.5, 0, 0.5, 0.5)) }),
  B(id: "bl", icon: "rectangle.inset.bottomleft.filled", title: "", run: { tile((0, 0.5, 0.5, 0.5)) }),
  B(id: "br", icon: "rectangle.inset.bottomright.filled", title: "", run: { tile((0.5, 0.5, 0.5, 0.5)) }),
  B(id: "wifi", icon: "wifi", title: "Wi-Fi", run: {
      let on = sh("/usr/sbin/networksetup", ["-getairportpower", "en0"]).hasSuffix("On")
      _ = sh("/usr/sbin/networksetup", ["-setairportpower", "en0", on ? "off" : "on"]) }),
  B(id: "dark", icon: "circle.lefthalf.filled", title: "Dark mode", run: {
      _ = sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"]) })]
]


// ---------- Spaces (private SkyLight, no extra permissions) ----------
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func skySym<T>(_ n: String, _ t: T.Type) -> T? { dlsym(sky, n).map { unsafeBitCast($0, to: T.self) } }
let cgsMain = skySym("CGSMainConnectionID", (@convention(c) () -> Int32).self)
let cgsDisplays = skySym("CGSCopyManagedDisplaySpaces", (@convention(c) (Int32) -> Unmanaged<CFArray>?).self)
let cgsSpacesForWindows = skySym("CGSCopySpacesForWindows", (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?).self)
struct SpaceInfo { let id: Int; let current: Bool; let icons: [NSImage] }
func loadSpaces() -> [SpaceInfo] {
    guard let cid = cgsMain?(), let arr = cgsDisplays?(cid)?.takeRetainedValue() as? [[String: Any]], let d = arr.first,
          let list = d["Spaces"] as? [[String: Any]] else { return [] }
    let cur = ((d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int) ?? -1
    var perSpace: [Int: [pid_t]] = [:]
    let wins = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in wins {
        guard (w[kCGWindowLayer as String] as? Int) == 0, let wid = w[kCGWindowNumber as String] as? Int,
              let pid = w[kCGWindowOwnerPID as String] as? Int32,
              let b = w[kCGWindowBounds as String] as? [String: Any], (b["Width"] as? Double ?? 0) > 80 else { continue }
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        if owner == "Dock" || owner == "Window Server" || owner == "MTMR 2026" { continue }
        for sp in (cgsSpacesForWindows?(cid, 7, [wid] as CFArray)?.takeRetainedValue() as? [Int]) ?? [] {
            if !(perSpace[sp]?.contains(pid) ?? false) { perSpace[sp, default: []].append(pid) }
        }
    }
    return list.compactMap { sp in
        guard let id = sp["ManagedSpaceID"] as? Int else { return nil }
        let icons = (perSpace[id] ?? []).prefix(4).compactMap { NSRunningApplication(processIdentifier: $0)?.icon }
        return SpaceInfo(id: id, current: id == cur, icons: icons)
    }
}
func spaceImage(_ n: Int, _ icons: [NSImage]) -> NSImage {
    let h: CGFloat = 22, w = 16 + CGFloat(max(icons.count, 1)) * 24
    return NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
        let t = NSAttributedString(string: "\(n)", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.white])
        t.draw(at: NSPoint(x: 2, y: 3))
        for (i, ic) in icons.enumerated() { ic.draw(in: NSRect(x: 16 + CGFloat(i) * 24, y: 1, width: 20, height: 20)) }
        return true
    }
}
let cgsSetSpace = skySym("CGSManagedDisplaySetCurrentSpace", (@convention(c) (Int32, CFString, Int) -> Void).self)
func log(_ m: String) { try? (m + "\n").appendToFile("/tmp/modbar.log") }
extension String { func appendToFile(_ p: String) throws {
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(data(using: .utf8)!); h.closeFile() } else { try write(toFile: p, atomically: true, encoding: .utf8) } } }
func goToSpace(_ target: Int) {
    let sp = loadSpaces()
    guard let ci = sp.firstIndex(where: { $0.current }), target != ci, target < sp.count else { return }
    log("goTo \(target) from \(ci) trusted=\(AXIsProcessTrusted())")
    // 1) keyboard: Control+Arrow (needs the fn/numpad flags the real arrow keys carry)
    let d = target - ci
    if AXIsProcessTrusted() {
        for _ in 0..<abs(d) { key(d > 0 ? 124 : 123, [.maskControl, .maskSecondaryFn, .maskNonCoalesced]); usleep(450_000) }
        usleep(200_000)
    }
    if loadSpaces().first(where: { $0.current })?.id == sp[ci].id {
        // 2) fallback: ask the window server directly
        log("keys did not switch; using CGSManagedDisplaySetCurrentSpace")
        if let cid = cgsMain?(), let arr = cgsDisplays?(cid)?.takeRetainedValue() as? [[String: Any]],
           let uuid = arr.first?["Display Identifier"] as? String { cgsSetSpace?(cid, uuid as CFString, sp[target].id) }
    }
}


// ---------- Clipboard history ----------
final class Clips: NSObject, NSScrubberDataSource, NSScrubberDelegate, NSScrubberFlowLayoutDelegate {
    enum Kind { case text(String), image(Data) }
    var items: [Kind] = []
    var last = NSPasteboard.general.changeCount
    var selfWrite = -1
    weak var scrubber: NSScrubber?
    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != last else { return }
        last = pb.changeCount
        if last == selfWrite { return }
        let types = pb.types?.map { $0.rawValue } ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { log("clip: skipped concealed"); return }
        if let t = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            items.removeAll { if case .text(let x) = $0 { return x == t } else { return false } }
            items.insert(.text(t), at: 0)
        } else if let d = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            items.insert(.image(d), at: 0)
        } else { log("clip: unsupported types \(types)"); return }
        if items.count > 30 { items.removeLast() }
        log("clip: now \(items.count) items")
        scrubber?.reloadData()
    }
    func oneLine(_ t: String) -> String { String(t.split(whereSeparator: { $0.isNewline }).joined(separator: " ").prefix(60)) }
    func numberOfItems(for scrubber: NSScrubber) -> Int { max(items.count, 1) }
    func scrubber(_ scrubber: NSScrubber, viewForItemAt i: Int) -> NSScrubberItemView {
        if items.isEmpty {
            let v = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("clip"), owner: nil) as! NSScrubberTextItemView
            v.textField.stringValue = "Clipboard history is empty — copy some text"; v.textField.font = .systemFont(ofSize: 13); return v
        }
        switch items[i] {
        case .text(let t):
            let v = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("clip"), owner: nil) as! NSScrubberTextItemView
            v.textField.stringValue = oneLine(t); v.textField.font = .systemFont(ofSize: 13); v.textField.lineBreakMode = .byTruncatingTail
            return v
        case .image(let d):
            let v = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("img"), owner: nil) as! NSScrubberImageItemView
            let src = NSImage(data: d) ?? NSImage()
            let box = NSSize(width: 60, height: 30), inner = NSRect(x: 8, y: 4, width: 44, height: 22)
            v.image = NSImage(size: box, flipped: false) { _ in
                let r = AVMakeRect(aspectRatio: src.size, insideRect: inner); src.draw(in: r); return true }
            return v
        }
    }
    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt i: Int) -> NSSize {
        if items.isEmpty { return NSSize(width: 330, height: 30) }
        switch items[i] {
        case .image: return NSSize(width: 60, height: 30)
        case .text(let t):
            let w = (oneLine(t) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 28
            return NSSize(width: min(max(w, 70), 230), height: 30)
        }
    }
    func scrubber(_ scrubber: NSScrubber, didSelectItemAt i: Int) {
        log("clip: tapped \(i) of \(items.count) ax=\(AXIsProcessTrusted())")
        guard !items.isEmpty, i >= 0, i < items.count else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        switch items[i] {
        case .text(let t): pb.setString(t, forType: .string)
        case .image(let d): pb.setData(d, forType: .png)
        }
        selfWrite = pb.changeCount; last = pb.changeCount
        log("clip: put item on pasteboard, types=\(pb.types?.map{$0.rawValue} ?? [])")
        scrubber.selectedIndex = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { scrubber.selectedIndex = -1 }
        if AXIsProcessTrusted() { DispatchQueue.global().async { key(9, .maskCommand) } }   // otherwise it is on the clipboard: just press V
    }
    func makeItem(_ id: NSTouchBarItem.Identifier) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: id)
        let sc = NSScrubber()
        sc.register(NSScrubberTextItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier("clip"))
        sc.register(NSScrubberImageItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier("img"))
        let l = NSScrubberFlowLayout(); l.itemSpacing = 6; sc.scrubberLayout = l
        sc.mode = .free; sc.dataSource = self; sc.delegate = self
        sc.showsAdditionalContentIndicators = true; sc.selectionBackgroundStyle = .roundedBackground
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.widthAnchor.constraint(equalToConstant: 640).isActive = true
        scrubber = sc; log("clip: showing \(items.count) items"); item.view = sc; return item
    }
}
let clips = Clips()

// ---------- Touch Bar ----------
final class Bar: NSObject, NSTouchBarDelegate {
    var current: String? = nil
    var touchBar: NSTouchBar?
    var spaceList: [SpaceInfo] = []
    var gen = 0
    func spaceIDs() -> [NSTouchBarItem.Identifier] { gen += 1; return [.flexibleSpace] + spaceList.indices.map { NSTouchBarItem.Identifier("modbar.sp.\(gen).\($0)") } + [.flexibleSpace] }
    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if id.rawValue.hasPrefix("modbar.sp."), let i = Int(id.rawValue.split(separator: ".").last ?? ""), i < spaceList.count {
            let sp = spaceList[i]
            let item = NSCustomTouchBarItem(identifier: id)
            let btn = NSButton(title: "", image: spaceImage(i + 1, sp.icons), target: self, action: #selector(spaceTap(_:)))
            btn.imagePosition = .imageOnly; btn.tag = i
            if sp.current { btn.bezelColor = .controlAccentColor }
            item.view = btn; return item
        }
        if id.rawValue == "modbar.clip" { return clips.makeItem(id) }
        guard let name = current, let b = bars[name]?.first(where: { "modbar.\($0.id)" == id.rawValue }) else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let btn = NSButton(title: b.title, image: NSImage(systemSymbolName: b.icon, accessibilityDescription: b.title)!, target: self, action: #selector(tap(_:)))
        btn.imagePosition = b.title.isEmpty ? .imageOnly : .imageLeading
        btn.identifier = NSUserInterfaceItemIdentifier(b.id)
        item.view = btn; return item
    }
    @objc func spaceTap(_ s: NSButton) {
        let i = s.tag
        DispatchQueue.global().async {
            goToSpace(i)
            DispatchQueue.main.async { if self.current == "control" { self.spaceList = loadSpaces(); self.touchBar?.defaultItemIdentifiers = self.spaceIDs() } }
        }
    }
    @objc func tap(_ s: NSButton) {
        guard let name = current, let b = bars[name]?.first(where: { $0.id == s.identifier?.rawValue }) else { return }
        DispatchQueue.global().async { b.run() }
    }
    func show(_ name: String) {
        guard name != current else { return }
        hide(); current = name
        let tb = NSTouchBar(); tb.delegate = self
        if name == "control" {
            spaceList = loadSpaces()
            tb.defaultItemIdentifiers = spaceIDs()
        } else {
            tb.defaultItemIdentifiers = [.flexibleSpace] + bars[name]!.map { NSTouchBarItem.Identifier("modbar.\($0.id)") } + (name == "command" ? [NSTouchBarItem.Identifier("modbar.clip")] : []) + [.flexibleSpace]
        }
        touchBar = tb
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
        if let m = class_getClassMethod(NSTouchBar.self, sel) { unsafeBitCast(method_getImplementation(m), to: Fn.self)(NSTouchBar.self, sel, tb, 1, nil) }
    }
    func hide() {
        guard let tb = touchBar else { current = nil; return }
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        if let m = class_getClassMethod(NSTouchBar.self, sel) { unsafeBitCast(method_getImplementation(m), to: Fn.self)(NSTouchBar.self, sel, tb) }
        touchBar = nil; current = nil
    }
}

if CommandLine.arguments.contains("--spaces") { for (i, sp) in loadSpaces().enumerated() { print(i + 1, sp.id, sp.current ? "CURRENT" : "", "apps:", sp.icons.count) }; exit(0) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
log("startup screenCapture=\(CGPreflightScreenCaptureAccess()) ax=\(AXIsProcessTrusted())")
if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
let bar = Bar()
var heldSince = Date.distantFuture, heldKey: String? = nil
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in clips.poll() }
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    let f = NSEvent.modifierFlags.intersection([.control, .option, .command, .shift])
    let k: String? = f == .control ? "control" : f == .option ? "option" : f == .command ? "command" : nil
    if k != heldKey { heldKey = k; heldSince = Date(); if k == nil { bar.hide() } }
    if let k = k, Date().timeIntervalSince(heldSince) > 0.35 { bar.show(k) }
    else if k == nil { bar.hide() }
}
app.run()
