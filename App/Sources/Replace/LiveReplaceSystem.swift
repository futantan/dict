// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The parts of a `ReplaceTarget` read on the accessibility queue; the app is added on the
/// main actor.
struct ReplaceSnapshot: Sendable {
  let element: AXElement
  let range: CFRange
  let valueBefore: String
  let axWritable: Bool
}

/// Snapshots the selection's field for replacing, or nil when it may not be replaced
/// (architecture 4.3). Accessibility queue only.
func replaceSnapshot(_ found: FoundSelection, kind: AppKind) -> ReplaceSnapshot? {
  guard let range = found.range, kind != .terminal, kind != .ownApp else { return nil }
  let element = found.element
  if let count = AX.int(element, AXNames.numberOfCharacters), count > maxFieldTextLength {
    return nil
  }
  let selectedTextSettable = isSettable(element, kAXSelectedTextAttribute)
  let value = AX.string(element, kAXValueAttribute).1
  guard
    isReplaceable(
      kind: kind, role: AX.string(element, kAXRoleAttribute).1,
      selectedTextSettable: selectedTextSettable,
      valueSettable: isSettable(element, kAXValueAttribute), value: value, range: range,
      selectedText: found.text),
    let value
  else { return nil }
  return ReplaceSnapshot(
    element: AXElement(raw: element), range: range, valueBefore: value,
    axWritable: selectedTextSettable)
}

/// The pure part of architecture 4.3. Chromium's contenteditable range offsets leave out
/// line breaks (measured), so only native fields compare the range with the value.
func isReplaceable(
  kind: AppKind, role: String?, selectedTextSettable: Bool, valueSettable: Bool,
  value: String?, range: CFRange?, selectedText: String
) -> Bool {
  guard kind != .terminal, kind != .ownApp,
    let role, [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
    selectedTextSettable || valueSettable,
    let value, value.utf16.count <= maxFieldTextLength,
    let range
  else { return false }
  guard kind == .native else { return true }
  let utf16 = value.utf16
  guard range.location >= 0, range.length >= 0, range.location + range.length <= utf16.count
  else { return false }
  let start = utf16.index(utf16.startIndex, offsetBy: range.location)
  let end = utf16.index(start, offsetBy: range.length)
  return String(utf16[start..<end]) == selectedText
}

private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
  var settable: DarwinBoolean = false
  return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
    && settable.boolValue
}

/// Reads the field the way `SystemReplaceWriter` checks it. Accessibility queue only.
func readField(_ element: AXUIElement, pid: pid_t) -> FieldReading? {
  let (valueError, value) = AX.string(element, kAXValueAttribute)
  if valueError == .invalidUIElement { return nil }
  let focused = AX.element(AX.application(pid), kAXFocusedUIElementAttribute).1
  return FieldReading(
    isFocused: focused.map { CFEqual($0, element) } ?? false,
    isSecure: AX.string(element, kAXSubroleAttribute).1 == AXNames.secureTextField,
    range: AX.range(element),
    selectedText: AX.string(element, kAXSelectedTextAttribute).1,
    value: value)
}

/// The real accessibility, clipboard and key posting.
@MainActor
final class LiveReplaceSystem: ReplaceSystem {
  private let queue: AXQueue
  private let clipboard: ClipboardGateway

  init(queue: AXQueue, clipboard: ClipboardGateway) {
    self.queue = queue
    self.clipboard = clipboard
  }

  func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

  func read(_ target: ReplaceTarget) async -> FieldReading? {
    let element = target.element
    let pid = target.app.pid
    return await queue.run { readField(element.raw, pid: pid) }
  }

  func writeSelectedText(_ text: String, into target: ReplaceTarget) async {
    let element = target.element
    let error = await queue.run { AX.set(element.raw, kAXSelectedTextAttribute, text as CFString) }
    if error != .success {
      Log.replace.info("accessibility write returned \(error.rawValue, privacy: .public)")
    }
  }

  func canPostKeys(to target: ReplaceTarget) -> Bool {
    AXIsProcessTrusted() && CGPreflightPostEventAccess()
      && !blocksKeyPosting(currentSecureInput(), targetPID: target.app.pid, kind: target.app.kind)
  }

  var clipboardDenied: Bool { clipboard.isAccessDenied }
  var clipboardChangeCount: Int { clipboard.changeCount }
  func snapshotClipboard() -> ClipboardSnapshot { clipboard.snapshot() }
  func writeClipboard(_ text: String) -> Int { clipboard.writeTransient(text) }
  func restoreClipboard(_ snapshot: ClipboardSnapshot) { clipboard.restore(snapshot) }

  func postPaste(to pid: pid_t) {
    postCommandKey(typing: "v", fallback: UInt16(kVK_ANSI_V), to: pid)
  }

  func sleep(_ duration: Duration) async {
    try? await Task.sleep(for: duration)
  }
}
