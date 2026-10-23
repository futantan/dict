// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Testing

@testable import DictApp

/// Architecture 4.3: when a selection may be replaced.
struct ReplaceTargetTests {
  private func replaceable(
    kind: AppKind = .native, role: String? = kAXTextAreaRole, selectedTextSettable: Bool = true,
    valueSettable: Bool = true, value: String? = "I saw teh cat.",
    range: CFRange? = CFRange(location: 6, length: 3), selected: String = "teh"
  ) -> Bool {
    isReplaceable(
      kind: kind, role: role, selectedTextSettable: selectedTextSettable,
      valueSettable: valueSettable, value: value, range: range, selectedText: selected)
  }

  @Test func aNativeTextAreaIsReplaceable() {
    #expect(replaceable())
    #expect(replaceable(role: kAXTextFieldRole))
    #expect(replaceable(role: kAXComboBoxRole))
  }

  @Test func terminalsAndDictItselfAreNot() {
    #expect(!replaceable(kind: .terminal))
    #expect(!replaceable(kind: .ownApp))
  }

  /// Read-only web text and other elements that are not text inputs.
  @Test func otherRolesAreNot() {
    #expect(!replaceable(role: "AXStaticText"))
    #expect(!replaceable(role: "AXWebArea"))
    #expect(!replaceable(role: nil))
  }

  /// Ghostty's text area reports neither as settable (measured).
  @Test func oneOfTheTwoAttributesMustBeSettable() {
    #expect(replaceable(selectedTextSettable: false))
    #expect(replaceable(valueSettable: false))
    #expect(!replaceable(selectedTextSettable: false, valueSettable: false))
  }

  @Test func theValueAndRangeMustBeReadable() {
    #expect(!replaceable(value: nil))
    #expect(!replaceable(range: nil))
    #expect(!replaceable(value: String(repeating: "a", count: 200_001)))
  }

  @Test func inANativeFieldTheRangeMustHoldTheSelection() {
    #expect(!replaceable(range: CFRange(location: 0, length: 3)))
    #expect(!replaceable(range: CFRange(location: 12, length: 5)))
  }

  /// Chromium's contenteditable ranges leave out line breaks (measured), so the range is
  /// not compared there.
  @Test func inChromiumTheRangeIsNotCompared() {
    #expect(replaceable(kind: .chromium, range: CFRange(location: 0, length: 3)))
    #expect(replaceable(kind: .electron, range: CFRange(location: 0, length: 3)))
  }
}
