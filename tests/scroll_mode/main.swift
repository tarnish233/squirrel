//
//  Scroll-mode integration harness.
//
//  Drives the real SquirrelInputController / SquirrelPanel with a real librime
//  session (isolated temporary user directory), checks the resulting state and
//  renders the panel to PNG files. See run.sh.
//

import AppKit
import Carbon.HIToolbox
import InputMethodKit

// Main.swift is not compiled into the harness; provide the paths it normally defines.
enum SquirrelApp {
  static let userDir = URL(fileURLWithPath: env("HARNESS_USER_DIR"), isDirectory: true)
  static let appDir = URL(fileURLWithPath: env("HARNESS_APP_DIR"), isDirectory: true)
  static let logDir = URL(fileURLWithPath: env("HARNESS_LOG_DIR"), isDirectory: true)
}

func env(_ name: String) -> String {
  guard let value = ProcessInfo.processInfo.environment[name] else { fatalError("missing \(name)") }
  return value
}
let variant = ProcessInfo.processInfo.environment["HARNESS_VARIANT"] ?? ""

/// Where the fake client reports its caret, in screen coordinates.
var caretRect = NSRect(x: 300, y: 600, width: 1, height: 18)

final class FakeClient: NSObject, IMKTextInput {
  var marked = ""
  var committed = [String]()

  func insertText(_ string: Any!, replacementRange: NSRange) {
    committed.append((string as? String) ?? (string as? NSAttributedString)?.string ?? "")
    marked = ""
  }
  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    marked = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
  }
  func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
  func markedRange() -> NSRange { NSRange(location: 0, length: (marked as NSString).length) }
  func attributedSubstring(from range: NSRange) -> NSAttributedString! { NSAttributedString() }
  func length() -> Int { 0 }
  func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
  func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
    lineRect?.pointee = caretRect
    return [:]
  }
  func validAttributesForMarkedText() -> [Any]! { [] }
  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
  func selectMode(_ modeIdentifier: String!) {}
  func supportsUnicode() -> Bool { true }
  func bundleIdentifier() -> String! { "im.rime.ohmyrime.harness" }
  func windowLevel() -> CGWindowLevel { 0 }
  func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
  func uniqueClientIdentifierString() -> String! { "harness" }
  func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { "" }
  func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

// MARK: - Helpers

func field<T>(_ object: Any, _ name: String) -> T? {
  var mirror: Mirror? = Mirror(reflecting: object)
  while let current = mirror {
    if let child = current.children.first(where: { $0.label == name }) {
      return child.value as? T
    }
    mirror = current.superclassMirror
  }
  return nil
}

struct Key {
  let chars: String
  let code: Int
  var mods: NSEvent.ModifierFlags = []
}

let letterCodes: [Character: Int] = [
  "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
  "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
  "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
  "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
  "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
  "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, " ": kVK_Space
]
let tab = Key(chars: "\t", code: kVK_Tab)
let shiftTab = Key(chars: "\u{19}", code: kVK_Tab, mods: [.shift])
let up = Key(chars: "\u{F700}", code: kVK_UpArrow, mods: [.numericPad, .function])
let down = Key(chars: "\u{F701}", code: kVK_DownArrow, mods: [.numericPad, .function])
let left = Key(chars: "\u{F702}", code: kVK_LeftArrow, mods: [.numericPad, .function])
let right = Key(chars: "\u{F703}", code: kVK_RightArrow, mods: [.numericPad, .function])
let escape = Key(chars: "\u{1B}", code: kVK_Escape)

var failures = 0
func check(_ condition: Bool, _ message: String) {
  print(condition ? "  ✓ \(message)" : "  ✗ \(message)")
  if !condition { failures += 1 }
}

// MARK: - Rime and app setup

setvbuf(stdout, nil, _IONBF, 0)
print("harness: starting")

let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool().pointee
let app = NSApplication.shared
// The preview puts real windows on screen; the tests keep everything invisible.
app.setActivationPolicy(variant == "preview" ? .accessory : .prohibited)
let delegate = SquirrelApplicationDelegate()
app.delegate = delegate

var traits = RimeTraits.rimeStructInit()
traits.setCString(env("HARNESS_SHARED_DIR"), to: \.shared_data_dir)
traits.setCString(SquirrelApp.userDir.path(), to: \.user_data_dir)
traits.setCString(SquirrelApp.logDir.path(), to: \.log_dir)
traits.setCString("Squirrel", to: \.distribution_code_name)
traits.setCString("鼠鬚管", to: \.distribution_name)
traits.setCString("harness", to: \.distribution_version)
traits.setCString("rime.squirrel-harness", to: \.app_name)
rimeAPI.setup(&traits)
rimeAPI.initialize(nil)
if rimeAPI.start_maintenance(true) {
  rimeAPI.join_maintenance_thread()
}
_ = rimeAPI.deploy_config_file("squirrel.yaml", "config_version")

let panel = SquirrelPanel(position: .zero)
delegate.panel = panel
delegate.loadSettings()

let client = FakeClient()
// IMK rejects non-proxy clients at init; handle(_:client:) picks up the client afterwards.
let controller: SquirrelInputController = SquirrelInputController(server: nil, delegate: nil, client: nil)!
let outDir = URL(fileURLWithPath: env("HARNESS_OUT_DIR"), isDirectory: true)

func press(_ key: Key) {
  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: key.mods, timestamp: 0, windowNumber: 0, context: nil,
                               characters: key.chars, charactersIgnoringModifiers: key.chars, isARepeat: false, keyCode: UInt16(key.code))!
  _ = controller.handle(event, client: client)
}
func type(_ text: String) {
  for char in text {
    press(Key(chars: String(char), code: letterCodes[char]!))
  }
}
func repeatPress(_ key: Key, _ times: Int) {
  for _ in 0..<times { press(key) }
}

var session: RimeSessionId { field(controller, "session") ?? 0 }
func allCandidates(_ count: Int = 60) -> [String] {
  rimeAPI.candidates(of: session, from: 0, count: count).map(\.text)
}

struct PanelState {
  let candidates: [String]
  let index: Int
  let page: Int
  let layout: SquirrelScrollLayout?
  let visible: Bool
}
func state() -> PanelState {
  PanelState(candidates: field(panel, "candidates") ?? [], index: field(panel, "index") ?? -1, page: field(panel, "page") ?? -1,
             layout: field(panel, "scrollLayout") ?? nil, visible: panel.isVisible)
}
func describe(_ title: String) -> PanelState {
  let current = state()
  let layout = current.layout.map { "rows=\(current.candidates.count / max(1, $0.rowSize)) highlightedRow=\($0.highlightedRow) above=\($0.hasRowsAbove) below=\($0.hasRowsBelow)" } ?? "collapsed"
  let highlighted = current.index >= 0 && current.index < current.candidates.count ? current.candidates[current.index] : "-"
  print("[\(title)] page=\(current.page) index=\(current.index) (\(highlighted)) \(layout) count=\(current.candidates.count)")
  return current
}

var snapshotCount = 0
func snapshot(_ name: String) {
  guard let view = panel.contentView else { return }
  view.displayIfNeeded()
  guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
  view.cacheDisplay(in: view.bounds, to: rep)
  snapshotCount += 1
  let url = outDir.appending(path: String(format: "%02d-%@.png", snapshotCount, name))
  try? rep.representation(using: .png, properties: [:])?.write(to: url)
  print("  → \(url.lastPathComponent) \(Int(view.bounds.width))×\(Int(view.bounds.height))")
}

// MARK: - Preview

/// A document with a picture beside it, so screenshots show how the panel background reads over
/// text and over colorful content.
final class BackdropView: NSView {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    let split = (bounds.width * 0.55).rounded()
    let picture = NSRect(x: split, y: 20, width: bounds.width - split - 20, height: bounds.height - 40)
    NSGradient(colors: [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple])?
      .draw(in: NSBezierPath(roundedRect: picture, xRadius: 16, yRadius: 16), angle: -50)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 7
    style.paragraphSpacing = 10
    let text = """
      候选框预览 Candidate panel preview
      落霞与孤鹜齐飞，秋水共长天一色。渔舟唱晚，响穷彭蠡之滨；雁阵惊寒，声断衡阳之浦。
      The quick brown fox jumps over the lazy dog. 0123456789
      遥襟甫畅，逸兴遄飞。爽籁发而清风生，纤歌凝而白云遏。睢园绿竹，气凌彭泽之樽；邺水朱华，光照临川之笔。四美具，二难并。穷睇眄于中天，极娱游于暇日。天高地迥，觉宇宙之无穷；兴尽悲来，识盈虚之有数。
      """
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
      .draw(in: NSRect(x: 24, y: 20, width: split - 48, height: bounds.height - 40))
  }
}

/// Shows the real panel over the backdrop and captures that screen region with screencapture,
/// which includes the glass background that offscreen snapshots cannot render.
func runPreview() {
  let backdropFrame = NSRect(x: 240, y: 280, width: 900, height: 480)
  let backdrop = NSWindow(contentRect: backdropFrame, styleMask: [.borderless], backing: .buffered, defer: false)
  backdrop.level = .screenSaver
  backdrop.hasShadow = false
  backdrop.contentView = BackdropView()
  // Show on whatever space is current, full-screen apps included.
  backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  backdrop.orderFrontRegardless()

  /// Whether only this process's windows are visible in the region (CGWindowList is front to
  /// back), so that a screenshot can never contain another app's content.
  func onlyOwnWindows(in region: NSRect) -> Bool {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    let screenHeight = NSScreen.screens[0].frame.height
    for window in windows {
      guard let bounds = (window[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { continue }
      let frame = NSRect(x: bounds.minX, y: screenHeight - bounds.maxY, width: bounds.width, height: bounds.height)
      guard frame.intersects(region), (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
      guard (window[kCGWindowOwnerPID as String] as? Int32) == getpid() else { return false }
      if (window[kCGWindowNumber as String] as? Int) == backdrop.windowNumber {
        return frame.contains(region)
      }
    }
    return false
  }
  caretRect = NSRect(x: backdropFrame.minX + 330, y: backdropFrame.maxY - 92, width: 1, height: 18)

  func capture(_ name: String, settle: Double = 0.5) {
    RunLoop.main.run(until: Date().addingTimeInterval(settle))
    let caretLine = NSRect(x: caretRect.minX - 60, y: caretRect.minY, width: 60, height: caretRect.height)
    let region = panel.frame.union(caretLine).insetBy(dx: -28, dy: -24).intersection(backdrop.frame).integral
    guard onlyOwnWindows(in: region) else {
      print("  ✗ \(name) skipped: other windows are visible over the preview (another space or app in front?)")
      failures += 1
      return
    }
    // screencapture takes top-left based coordinates of the main display
    let screenHeight = NSScreen.screens[0].frame.height
    let url = outDir.appending(path: "\(name).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R\(Int(region.minX)),\(Int(screenHeight - region.maxY)),\(Int(region.width)),\(Int(region.height))", url.path]
    try? task.run()
    task.waitUntilExit()
    // Where the panel is in the screenshot (points from the top left), for tests/scroll_mode/measure.py.
    print(String(format: "  → %@ panel %.0f×%.0f at %.0f,%.0f", url.lastPathComponent, panel.frame.width, panel.frame.height,
                 panel.frame.minX - region.minX, region.maxY - panel.frame.maxY))
    if let view: SquirrelView = field(panel, "view") {
      // Layout metrics for tuning paddings: line fragments in text container coordinates.
      var lines = [String]()
      view.textLayoutManager.enumerateTextLayoutFragments(from: view.textLayoutManager.documentRange.location, options: []) { fragment in
        let frame = fragment.layoutFragmentFrame
        for line in fragment.textLineFragments {
          let bounds = line.typographicBounds
          lines.append(String(format: "y %.1f+%.1f h %.1f", frame.minY, bounds.minY, bounds.height))
        }
        return true
      }
      let ranges = view.candidateRanges, index = view.hilightedIndex
      if index >= 0 && index < ranges.count {
        let text = ((view.textContentStorage.attributedString?.string ?? "") as NSString).substring(with: ranges[index])
        let capsule = view.highlightCapsule(for: ranges[index], at: index) ?? .zero
        print(String(format: "    highlight %@ scalars %@ capsule x %.1f w %.1f", text.debugDescription,
                     text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " "), capsule.minX, capsule.width))
      }
      print(String(format: "    content %.1f×%.1f inset %.1f,%.1f lines: ", view.contentRect.width, view.contentRect.height,
                   view.textView.textContainerInset.width, view.textView.textContainerInset.height) + lines.prefix(3).joined(separator: " | "))
    }
  }

  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    print("== \(name)")
    NSApp.appearance = NSAppearance(named: appearance)
    backdrop.appearance = NSApp.appearance
    backdrop.contentView?.needsDisplay = true
    type("nihao")
    capture("\(name)-1-nihao")
    press(escape)
    type("shi")
    press(tab)
    repeatPress(right, 2)
    capture("\(name)-2-grid")
    press(escape)
    press(Key(chars: "R", code: kVK_ANSI_R, mods: [.shift]))
    type("123")
    capture("\(name)-3-comments")
    press(escape)
    // Long candidates: one line as wide as needed, cut short only past the width limit.
    let caret = caretRect
    caretRect.origin.x = backdropFrame.minX + 40
    // A wider backdrop for the wide grid.
    let screenWidth = NSScreen.screens[0].frame.width
    backdrop.setFrame(NSRect(x: backdropFrame.minX, y: backdropFrame.minY, width: min(1240, screenWidth - backdropFrame.minX - 8),
                             height: backdropFrame.height), display: true)
    type("macos")
    capture("\(name)-6-long")
    press(tab)
    capture("\(name)-7-long-grid")
    press(escape)
    SquirrelPanel.rowWidthLimit = 600
    type("macos")
    capture("\(name)-8-cut")
    press(tab)
    capture("\(name)-9-cut-grid")
    press(escape)
    SquirrelPanel.rowWidthLimit = nil
    caretRect = caret
    backdrop.setFrame(backdropFrame, display: true)
  }
  // Motion: sample the window size while the grid expands and collapses.
  func sample(_ name: String, _ action: () -> Void) {
    var sizes = [String]()
    let start = CACurrentMediaTime()
    action()
    while CACurrentMediaTime() - start < 0.32 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      sizes.append(String(format: "%.0f:%.0f×%.0f", (CACurrentMediaTime() - start) * 1000, panel.frame.width, panel.frame.height))
    }
    print("  \(name): " + sizes.joined(separator: " "))
  }
  print("== motion")
  NSApp.appearance = NSAppearance(named: .aqua)
  backdrop.appearance = NSApp.appearance
  backdrop.contentView?.needsDisplay = true
  type("shi")
  RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  sample("expand (Tab)") { press(tab) }
  press(shiftTab)  // back to the first row
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  sample("collapse (⇧Tab on the first row)") { press(shiftTab) }
  sample("expand again (↓)") { press(down) }
  press(up)  // back to the first row
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  sample("reverse mid-way (↑ collapses, ↓ after 60 ms)") {
    press(up)  // first row: collapse…
    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
    press(down)  // …and expand again before it ends
  }
  press(escape)
  // Mid-way frames, slowed down 20 times.
  SquirrelPanel.motionTimeScale = 20
  type("shi")
  RunLoop.main.run(until: Date().addingTimeInterval(0.6))
  press(tab)
  capture("light-4-expanding", settle: 0.12)
  RunLoop.main.run(until: Date().addingTimeInterval(4.2))
  press(shiftTab)
  press(shiftTab)
  capture("light-5-collapsing", settle: 0.25)
  RunLoop.main.run(until: Date().addingTimeInterval(3.4))
  SquirrelPanel.motionTimeScale = 1
  press(escape)

  panel.hide()
  backdrop.orderOut(nil)
  rimeAPI.finalize()
  exit(failures == 0 ? 0 : 1)
}

// MARK: - Scenarios

if variant == "preview" {
  runPreview()
}

if variant == "visual" {
  print("== V1. phrases, preedit line and paging arrows")
  type("shishi")
  snapshot("visual-collapsed")
  repeatPress(tab, 2)
  _ = describe("shishi Tab×2")
  snapshot("visual-phrases")
  press(escape)
  print("== V2. a long sentence in the first column")
  type("womenyiqiqushangxue")
  press(tab)
  _ = describe("sentence Tab")
  snapshot("visual-sentence")
  press(escape)
  panel.hide()
  rimeAPI.finalize()
  exit(0)
}

print("== 1. collapsed")
type("shi")
let full = allCandidates()
print("  first 25: \(full.prefix(25).joined(separator: " "))")
var s = describe("shi")
check(s.layout == nil && s.page == 0 && s.candidates.count == 5, "single row of 5 candidates")
check(s.candidates == Array(full.prefix(5)), "row shows page 0")
snapshot("collapsed")

print("== 2. Tab expands and moves to row 2")
press(tab)
s = describe("Tab")
check(s.layout != nil && s.page == 1, "expanded on page 1")
check(s.candidates == Array(full.prefix(20)), "4 rows = candidates 0..<20")
check(s.index == 5 && s.layout?.highlightedRow == 1, "highlight on row 2, column 1")
check(s.layout?.hasRowsBelow == true && s.layout?.hasRowsAbove == false, "more rows below only")
snapshot("tab-expanded")

print("== 3. → → keeps moving within the row, ↓ keeps the column")
repeatPress(right, 2)
s = describe("→→")
check(s.index == 7, "highlight at row 2 column 3")
press(down)
s = describe("↓")
check(s.page == 2 && s.index == 12, "↓ to row 3, same column")
snapshot("down-same-column")

print("== 4. Tab scrolls the window")
repeatPress(tab, 2)
s = describe("Tab×2")
check(s.page == 4 && s.layout?.highlightedRow == 3 && s.layout?.hasRowsAbove == true, "page 4 on the last visible row, rows above hidden")
check(s.candidates == Array(full[5..<25]), "window shows pages 1...4")
check(s.index == 17, "column kept (row 4, column 3)")
snapshot("scrolled")

print("== 5. Shift+Tab back to the first row, then ↑ collapses")
repeatPress(shiftTab, 4)
s = describe("⇧Tab×4")
check(s.page == 0 && s.layout != nil && s.index == 2, "back on row 1 (still expanded), column kept")
press(up)
s = describe("↑")
check(s.layout == nil && s.page == 0 && s.candidates == Array(full.prefix(5)), "↑ on the first row collapses")
snapshot("collapsed-again")

print("== 6. Shift+Tab on the first row also collapses")
press(tab)
press(shiftTab)
s = describe("Tab ⇧Tab")
check(s.layout != nil && s.page == 0, "expanded on row 1")
press(shiftTab)
s = describe("⇧Tab")
check(s.layout == nil, "collapsed")

print("== 7. digits select from the highlighted row")
press(tab)
type("2")
check(client.committed.last == full[6], "2 on row 2 commits candidate #7 (\(full[6])), got \(client.committed.last ?? "nil")")
s = describe("after commit")
check(!s.visible || s.candidates.isEmpty, "panel hidden after commit")

print("== 8. mouse selection maps to the global index")
type("shi")
repeatPress(tab, 2)
// Committing in scenario 7 taught librime a new order, so read the live list.
let live = allCandidates()
_ = controller.selectCandidate(3)
check(client.committed.last == live[3], "click on row 1 column 4 commits \(live[3]), got \(client.committed.last ?? "nil")")
type("shi")
repeatPress(tab, 6)
s = describe("Tab×6")
let clickIndex = s.candidates.count - 1
let expected = s.candidates[clickIndex]
_ = controller.selectCandidate(clickIndex)
check(client.committed.last == expected, "click on the last visible cell commits \(expected), got \(client.committed.last ?? "nil")")

print("== 9. librime paging keys (= -) expand too; scroll wheel up collapses")
type("shi")
type("=")
s = describe("=")
check(s.layout != nil && s.page == 1, "= expands")
type("-")
s = describe("-")
check(s.layout != nil && s.page == 0, "- back to row 1 (expanded)")
_ = controller.page(up: true)
s = describe("wheel up")
check(s.layout == nil, "wheel up on the first row collapses")
_ = controller.page(up: false)
s = describe("wheel down")
check(s.layout != nil && s.page == 1, "wheel down expands")

print("== 10. new input collapses")
type("i")
s = describe("shii")
check(s.layout == nil && s.page == 0, "typing collapses the grid")
press(tab)
s = describe("Tab")
check(s.layout != nil, "expands again")
snapshot("new-input-expanded")
press(escape)
s = describe("Esc")
check(!s.visible, "Esc clears")

print("== 11. a single page has nothing to expand")
var singlePageInput: String?
for input in ["zhuai", "nou", "cei", "fiao", "den", "nun", "shei"] {
  type(input)
  let total = rimeAPI.candidates(of: session, from: 0, count: 100).count
  press(escape)
  print("  \(input): \(total) candidates")
  if total > 0 && total <= 5 {
    singlePageInput = input
    break
  }
}
if let input = singlePageInput {
  type(input)
  press(tab)
  s = describe("\(input) Tab")
  check(s.layout == nil && s.page == 0, "Tab on a single page stays collapsed")
  press(escape)
} else {
  print("  (no single-page input found, skipped)")
}

print("== 12. hover highlight on another row (the update(update: false) path used by mouseMoved)")
type("shi")
press(tab)
s = describe("Tab")
if let layout = s.layout {
  panel.update(preedit: field(panel, "preedit") ?? "", selRange: field(panel, "selRange") ?? .empty, caretPos: field(panel, "caretPos") ?? 0,
               candidates: s.candidates, comments: field(panel, "comments") ?? [], labels: field(panel, "labels") ?? [],
               highlighted: 13, page: s.page, lastPage: field(panel, "lastPage") ?? false, scroll: layout, update: false)
  check(state().index == s.index && state().layout != nil, "hover keeps librime's highlight and the grid")
  snapshot("hover-row3")
}
press(escape)

print("== 13. rows stay on one line; past the width limit the widest candidates are cut short")
let panelView: SquirrelView = field(panel, "view")!
func lineCount() -> Int {
  var lines = 0
  panelView.textLayoutManager.enumerateTextLayoutFragments(from: panelView.textLayoutManager.documentRange.location, options: []) { fragment in
    lines += fragment.textLineFragments.count
    return true
  }
  return lines
}
func cellRects() -> [NSRect] {
  panelView.candidateRanges.map { range in panelView.convert(range: range).map { panelView.contentRect(range: $0) } ?? .zero }
}
func shownCandidates() -> [String] {
  let string = (panelView.textContentStorage.attributedString?.string ?? "") as NSString
  return panelView.candidateRanges.map { string.substring(with: $0) }
}
let longInput = "zhonghuarenmingongheguowansui"
type(longInput)
let longRow = allCandidates(5)
let naturalWidth = panelView.contentRect.width
let cellWidths = cellRects().map(\.width).sorted(by: >)
print("  natural row \(Int(naturalWidth)) pt, cells \(cellWidths.map { Int($0) }): \(shownCandidates())")
check(lineCount() == 1, "the collapsed row is one line")
press(escape)
// Leave room for the widest cell only halfway down to the next widest.
let rowLimit = (naturalWidth - (cellWidths[0] - cellWidths[1]) / 2).rounded(.down)
SquirrelPanel.rowWidthLimit = rowLimit
type(longInput)
var shown = shownCandidates()
print("  limited to \(Int(rowLimit)) pt: \(Int(panelView.contentRect.width)) pt \(shown)")
check(lineCount() == 1, "still one line")
check(panelView.contentRect.width <= rowLimit + 1, "the row fits the limit")
check(shown.first?.contains("…") == true && shown.dropFirst().allSatisfy { !$0.contains("…") }, "only the widest candidate is cut short")
/// Whether a shown cell is its candidate cut short at the end: the text before … starts the candidate.
func isCutShort(_ cell: String, _ candidate: String) -> Bool {
  guard let start = cell.range(of: String(candidate.prefix(1)))?.lowerBound, let end = cell.range(of: "…")?.lowerBound, start < end else { return false }
  return candidate.hasPrefix(cell[start..<end])
}
check(shown.count == longRow.count && shown.indices.allSatisfy { i in
  shown[i].hasPrefix("\(i + 1)") && (shown[i].contains(longRow[i]) || isCutShort(shown[i], longRow[i]))
}, "cut short at the end, labels kept")
press(tab)
s = describe("Tab")
shown = shownCandidates()
let rows = s.candidates.count / max(1, s.layout?.rowSize ?? 1)
let rects = cellRects()
print("  grid \(Int(panelView.contentRect.width)) pt, \(rows) rows: \(shown)")
check(lineCount() == rows, "every grid row is one line")
check(panelView.contentRect.width <= rowLimit + 1, "the grid fits the limit")
let rowSize = s.layout?.rowSize ?? 1
check((0..<rowSize).allSatisfy { column in
  let starts = stride(from: column, to: rects.count, by: rowSize).map { rects[$0].minX }
  return (starts.max() ?? 0) - (starts.min() ?? 0) < 0.5
}, "columns stay aligned")
press(shiftTab)
press(shiftTab)
type("1")
check(client.committed.last == longRow[0], "1 commits the whole candidate \(longRow[0]), got \(client.committed.last ?? "nil")")
SquirrelPanel.rowWidthLimit = nil

print("")
print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
panel.hide()
rimeAPI.finalize()
exit(failures == 0 ? 0 : 1)
