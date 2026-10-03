// SPDX-License-Identifier: GPL-3.0-or-later
//
// End-to-end smoke test: launches the built app in the background, waits until its
// menu bar item shows up, then terminates it.
// It inspects the app through the Accessibility API only: no focus changes, no clicks,
// no key events. The process running it (your terminal) needs Accessibility permission.
//
// Usage: swift scripts/smoke-test.swift "path/to/App.app"

import ApplicationServices
import Foundation

nonisolated(unsafe) var launched: Process?

func fail(_ message: String) -> Never {
  if let launched, launched.isRunning { launched.terminate() }
  FileHandle.standardError.write(Data("smoke-test: FAIL: \(message)\n".utf8))
  exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

/// Accessibility descriptions of the app's menu bar items (its "extras" menu bar).
func menuBarItemDescriptions(pid: pid_t) -> [String] {
  let app = AXUIElementCreateApplication(pid)
  guard let extras = attribute(app, "AXExtrasMenuBar"),
    CFGetTypeID(extras) == AXUIElementGetTypeID(),
    let items = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
  else { return [] }
  return items.map { attribute($0, kAXDescriptionAttribute) as? String ?? "" }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fail("usage: smoke-test.swift <path to .app>") }
let appURL = URL(fileURLWithPath: arguments[1])
guard let bundle = Bundle(url: appURL), let executable = bundle.executableURL else {
  fail("no app bundle at \(appURL.path)")
}
let expectedName =
  bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
  ?? appURL.deletingPathExtension().lastPathComponent
guard AXIsProcessTrusted() else {
  fail("this terminal lacks Accessibility permission (System Settings > Privacy & Security)")
}

let process = Process()
process.executableURL = executable
do { try process.run() } catch { fail("could not launch: \(error)") }
launched = process
let pid = process.processIdentifier

let timeout: TimeInterval = 15
let deadline = Date().addingTimeInterval(timeout)
var found = false
while !found && Date() < deadline {
  guard process.isRunning else { fail("app exited early with status \(process.terminationStatus)") }
  found = menuBarItemDescriptions(pid: pid).contains(expectedName)
  if !found { Thread.sleep(forTimeInterval: 0.2) }
}

process.terminate()
process.waitUntilExit()
guard found else {
  fail("menu bar item \"\(expectedName)\" did not appear within \(Int(timeout)) s")
}
print("smoke-test: PASS: \"\(expectedName)\" (pid \(pid)) launched, showed its menu bar item, quit")
