import AppKit
import CoreAudio
import Darwin

// --- instant volume via CoreAudio (no osascript) ---
func outDevice() -> AudioDeviceID {
    var dev = AudioDeviceID(0); var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &dev)
    return dev
}
let dev = outDevice()
var volAddr = AudioObjectPropertyAddress(mSelector: 0x766D7663 /* 'vmvc' */, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
func getVol() -> Float {
    var v: Float32 = 0; var sz = UInt32(4)
    AudioObjectGetPropertyData(dev, &volAddr, 0, nil, &sz, &v); return v
}
func setVol(_ v: Float) { var x = Float32(v); AudioObjectSetPropertyData(dev, &volAddr, 0, nil, 4, &x) }
func deviceName() -> String {
    var name: Unmanaged<CFString>?; var sz = UInt32(MemoryLayout<CFString?>.size)
    var b = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &b, 0, nil, &sz, &name) == 0, let n = name?.takeRetainedValue() else { return "Volume" }
    return n as String
}

let args = Array(CommandLine.arguments.dropFirst())
let isBright = args.first == "b"
let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
typealias DSGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias DSSet = @convention(c) (UInt32, Float) -> Int32
func getBright() -> Float {
    guard let f = dlsym(ds, "DisplayServicesGetBrightness") else { return 0 }
    var b: Float = 0; _ = unsafeBitCast(f, to: DSGet.self)(CGMainDisplayID(), &b); return b
}
func setBright(_ v: Float) {
    guard let f = dlsym(ds, "DisplayServicesSetBrightness") else { return }
    _ = unsafeBitCast(f, to: DSSet.self)(CGMainDisplayID(), v)
}
func getLevel() -> Float { isBright ? getBright() : getVol() }
func setLevel(_ v: Float) { if isBright { setBright(v) } else { setVol(v) } }
let pidFile = "/tmp/volhud.pid"
func isVolhud(_ pid: Int32) -> Bool {
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return false }
    return String(cString: buf).hasSuffix("/volhud")
}
let delta = Float(Int((isBright ? args.dropFirst().first : args.first) ?? "0") ?? 0) / 100
var vol = max(0, min(1, getLevel() + delta))
if delta != 0 { setLevel(vol) }
// a pill is already on screen: just tell it to refresh, no new window, no blink
let myMode = isBright ? "b" : "v"
if let t = try? String(contentsOfFile: pidFile) {
    let parts = t.split(separator: " ")
    if parts.count == 2, let old = Int32(parts[0]), old != ProcessInfo.processInfo.processIdentifier, isVolhud(old) {
        if String(parts[1]) == myMode { kill(old, SIGUSR1); exit(0) }   // same pill: refresh in place
        kill(old, SIGTERM)                                               // other kind of pill: replace
    }
}
try? "\(ProcessInfo.processInfo.processIdentifier) \(myMode)".write(toFile: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let W: CGFloat = 250, H: CGFloat = 54
let vf = NSScreen.main!.visibleFrame
let win = NSWindow(contentRect: NSRect(x: vf.maxX - W - 20, y: vf.maxY - H - 8, width: W, height: H),
                   styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver; win.isOpaque = false; win.backgroundColor = .clear
win.ignoresMouseEvents = true; win.hasShadow = false
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

let label = NSTextField(labelWithString: isBright ? "Display" : deviceName())
label.font = .systemFont(ofSize: 11.5, weight: .semibold); label.textColor = .white
label.frame = NSRect(x: 20, y: 31, width: W - 40, height: 15)
content.addSubview(label)
func leftName(_ v: Float) -> String { isBright ? (v < 0.5 ? "sun.min.fill" : "sun.max") : (v == 0 ? "speaker.slash.fill" : "speaker.fill") }
func icon(_ n: String, _ x: CGFloat, _ w: CGFloat) -> NSImageView {
    let v = NSImageView(image: NSImage(systemSymbolName: n, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))!)
    v.contentTintColor = .white; v.frame = NSRect(x: x, y: 8, width: w, height: 14); return v
}
let leftIcon = icon(leftName(vol), 20, 14)
content.addSubview(leftIcon)
content.addSubview(icon(isBright ? "sun.max.fill" : "speaker.wave.3.fill", W - 20 - 20, 20))
let trackX: CGFloat = 20 + 14 + 8, trackW: CGFloat = W - trackX - (20 + 20 + 8)
let track = NSView(frame: NSRect(x: trackX, y: 13, width: trackW, height: 4))
track.wantsLayer = true; track.layer?.cornerRadius = 2; track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
let fill = NSView(frame: NSRect(x: 0, y: 0, width: trackW * CGFloat(vol), height: 4))
fill.wantsLayer = true; fill.layer?.cornerRadius = 2; fill.layer?.backgroundColor = NSColor.white.cgColor
track.addSubview(fill); content.addSubview(track)

let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: W, height: H))
glass.cornerRadius = H * 0.25
glass.style = .clear
glass.tintColor = NSColor.white.withAlphaComponent(0.0)
glass.contentView = content
content.wantsLayer = true
content.layer?.cornerRadius = H * 0.25
content.layer?.borderWidth = 1
content.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
win.contentView = glass
win.orderFrontRegardless()
var hideTimer: Timer?
func armTimer() {
    hideTimer?.invalidate()
    hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; win.animator().alphaValue = 0 }) { exit(0) }
    }
}
func refresh() {
    let v = max(0, min(1, getLevel()))
    fill.frame.size.width = trackW * CGFloat(v)
    leftIcon.image = NSImage(systemSymbolName: leftName(v), accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
    NSAnimationContext.beginGrouping(); NSAnimationContext.current.duration = 0; win.animator().alphaValue = 1; NSAnimationContext.endGrouping()
    win.alphaValue = 1
    armTimer()
}
signal(SIGUSR1, SIG_IGN)
let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
src.setEventHandler { refresh() }
src.resume()
armTimer()
app.run()
