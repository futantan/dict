// SPDX-License-Identifier: GPL-3.0-or-later
//
// Window activation test: launches the built app the way `open` does (Launch Services, not
// activated) and checks that each of its own windows comes up in front and key:
// - the first-run window on a fresh launch,
// - Settings… and About from the menu bar item, pressed through the Accessibility API,
// - the first-run window or Settings when the running app is opened again (reopen event).
// Each case runs in a new instance that is quit afterwards. The cases pass
// `-onboarding.completed NO` or `YES`, an argument-domain override, so the user's
// preferences are read but never written.
// It takes focus, so it holds /private/tmp/dict-ui.lock while it runs. The process running
// it (your terminal) needs Accessibility permission.
//
// Usage: swift scripts/window-test.swift "path/to/App.app"

import AppKit
import ApplicationServices

let lockPath = "/private/tmp/dict-ui.lock"
let timeout: TimeInterval = 10
nonisolated(unsafe) var launched: NSRunningApplication?
nonisolated(unsafe) var holdsLock = false

func quitLaunched() {
  guard let app = launched else { return }
  app.terminate()
  let deadline = Date().addingTimeInterval(5)
  while !app.isTerminated && Date() < deadline { spin(0.1) }
  if !app.isTerminated { app.forceTerminate() }
  launched = nil
}

func finish(_ status: Int32) -> Never {
  quitLaunched()
  if holdsLock { rmdir(lockPath) }
  exit(status)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("window-test: FAIL: \(message)\n".utf8))
  finish(1)
}

/// Waits while serving the main run loop, which delivers NSRunningApplication updates.
func spin(_ seconds: TimeInterval) {
  RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func waitFor<T>(_ what: String, _ probe: () -> T?, diagnose: () -> String = { "" }) -> T {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if let value = probe() { return value }
    spin(0.2)
  }
  fail("\(what) within \(Int(timeout)) s\(diagnose())")
}

// MARK: - Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
  guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID()
  else { return nil }
  return unsafeBitCast(value, to: AXUIElement.self)
}

func children(_ parent: AXUIElement) -> [AXUIElement] {
  attribute(parent, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func title(_ element: AXUIElement) -> String {
  attribute(element, kAXTitleAttribute) as? String ?? ""
}

/// The app's menu bar item, found by its accessibility description (the app name).
func menuBarItem(pid: pid_t, name: String) -> AXUIElement? {
  let app = AXUIElementCreateApplication(pid)
  guard let extras = element(app, "AXExtrasMenuBar") else { return nil }
  return children(extras).first { attribute($0, kAXDescriptionAttribute) as? String == name }
}

/// The items of the menu bar item's open menu.
func openMenuItems(_ item: AXUIElement) -> [AXUIElement]? {
  guard let menu = children(item).first else { return nil }
  let items = children(menu)
  return items.isEmpty ? nil : items
}

// MARK: - Window state

struct WindowRow {
  var pid: pid_t
  var owner: String
  var bounds: CGRect
  var alpha: Double
}

/// On-screen windows of the normal level, front to back.
func normalWindows() -> [WindowRow] {
  let info =
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
  return info.compactMap { row in
    guard row[kCGWindowLayer as String] as? Int == 0,
      let pid = row[kCGWindowOwnerPID as String] as? pid_t,
      let boundsInfo = row[kCGWindowBounds as String] as? NSDictionary,
      let bounds = CGRect(dictionaryRepresentation: boundsInfo)
    else { return nil }
    return WindowRow(
      pid: pid, owner: row[kCGWindowOwnerName as String] as? String ?? "?", bounds: bounds,
      alpha: row[kCGWindowAlpha as String] as? Double ?? 0)
  }
}

func onAScreen(_ bounds: CGRect) -> Bool {
  var count: UInt32 = 0
  CGGetActiveDisplayList(0, nil, &count)
  var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
  CGGetActiveDisplayList(count, &displays, &count)
  return displays.contains { CGDisplayBounds($0).contains(bounds) }
}

func state(of app: NSRunningApplication) -> String {
  let rows = normalWindows().prefix(3).map {
    "\($0.owner)[\($0.pid)] \(Int($0.bounds.minX)),\(Int($0.bounds.minY)) "
      + "\(Int($0.bounds.width))x\(Int($0.bounds.height)) alpha \($0.alpha)"
  }
  let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
  return "; active \(app.isActive), frontmost app \(front), front windows: "
    + rows.joined(separator: " | ")
}

/// Waits until the app is active, its window is the frontmost normal window, fully on a
/// screen and opaque, and that window is the app's focused (key) window.
func expectFrontAndKey(_ app: NSRunningApplication, _ what: String) -> String {
  let pid = app.processIdentifier
  return waitFor(
    "\(what) did not come up in front and key",
    {
      guard app.isActive, let front = normalWindows().first, front.pid == pid,
        front.alpha > 0, onAScreen(front.bounds),
        let focused = element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
      else { return nil }
      return "\(what) \"\(title(focused))\" in front and key, "
        + "\(Int(front.bounds.width))x\(Int(front.bounds.height)) at "
        + "\(Int(front.bounds.minX)),\(Int(front.bounds.minY))"
    }, diagnose: { state(of: app) })
}

// MARK: - Cases

let appURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")
guard CommandLine.arguments.count == 2, let bundle = Bundle(url: appURL) else {
  fail("usage: window-test.swift <path to .app>")
}
let appName =
  bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
  ?? appURL.deletingPathExtension().lastPathComponent
guard AXIsProcessTrusted() else {
  fail("this terminal lacks Accessibility permission (System Settings > Privacy & Security)")
}

func launch(_ arguments: [String]) -> NSRunningApplication {
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.arguments = arguments
  configuration.activates = false
  configuration.createsNewApplicationInstance = true
  nonisolated(unsafe) var result: Result<NSRunningApplication, any Error>?
  NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
    result = app.map { .success($0) } ?? .failure(error ?? CocoaError(.fileNoSuchFile))
  }
  let outcome = waitFor("Launch Services did not launch the app", { result })
  switch outcome {
  case .success(let app):
    launched = app
    return app
  case .failure(let error): fail("could not launch: \(error)")
  }
}

/// Opens the menu bar item's menu and presses the item `pick` chooses.
func pressMenuItem(_ app: NSRunningApplication, _ what: String, _ pick: ([AXUIElement]) -> Int?) {
  let item = waitFor(
    "menu bar item \"\(appName)\" did not appear",
    { menuBarItem(pid: app.processIdentifier, name: appName) })
  AXUIElementPerformAction(item, kAXPressAction as CFString)
  let items = waitFor("the menu did not open", { openMenuItems(item) })
  guard let index = pick(items) else { fail("no \(what) item in the menu") }
  AXUIElementPerformAction(items[index], kAXPressAction as CFString)
}

while mkdir(lockPath, 0o755) != 0 { spin(2) }
holdsLock = true

var passed: [String] = []

let fresh = launch(["-onboarding.completed", "NO"])
passed.append(expectFrontAndKey(fresh, "first-run window"))
quitLaunched()

// Settings… is the item with the ⌘, shortcut; About follows it.
let settingsIndex: ([AXUIElement]) -> Int? = { items in
  items.firstIndex { attribute($0, kAXMenuItemCmdCharAttribute) as? String == "," }
}
for (what, pick) in [
  ("Settings window", settingsIndex),
  ("About panel", { settingsIndex($0).map { $0 + 1 } }),
] {
  let app = launch(["--no-onboarding"])
  pressMenuItem(app, what, pick)
  passed.append(expectFrontAndKey(app, what))
  quitLaunched()
}

// Opening Dict again while it runs, after launching it with no window: the reopen Apple
// event is what Finder, Spotlight and `open` send to a running app. It goes to this
// instance's pid, because another copy of the app may be running too.
for (completed, what) in [
  ("NO", "first-run window on reopen"), ("YES", "Settings window on reopen"),
] {
  let app = launch(["--no-onboarding", "-onboarding.completed", completed])
  _ = waitFor(
    "menu bar item \"\(appName)\" did not appear",
    { menuBarItem(pid: app.processIdentifier, name: appName) })
  spin(0.5)
  if let front = normalWindows().first, front.pid == app.processIdentifier {
    fail("a window showed before reopening")
  }
  let reopen = NSAppleEventDescriptor(
    eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
    targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
  do {
    _ = try reopen.sendEvent(options: [.noReply], timeout: 5)
  } catch {
    fail("could not send the reopen event: \(error)")
  }
  passed.append(expectFrontAndKey(app, what))
  quitLaunched()
}

for line in passed { print("window-test: PASS: \(line)") }
finish(0)
