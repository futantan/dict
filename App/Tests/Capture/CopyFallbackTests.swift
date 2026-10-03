// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import DictApp

struct FallbackDecisionTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let failure: CaptureFailure
    let kind: AppKind
    let policy: ClipboardPolicy
    let expected: Bool
    var testDescription: String { "\(failure) in \(kind) with \(policy) → \(expected)" }
  }

  static let cases: [Case] = [
    Case(failure: .unreadable(axError: -25212), kind: .native, policy: .allowed, expected: true),
    Case(failure: .unreadable(axError: nil), kind: .chromium, policy: .allowed, expected: true),
    Case(failure: .unreadable(axError: -25212), kind: .native, policy: .never, expected: false),
    Case(
      failure: .nothingSelected(fieldText: nil), kind: .native, policy: .allowed, expected: false),
    Case(
      failure: .nothingSelected(fieldText: nil), kind: .terminal, policy: .allowed,
      expected: false),
    Case(
      failure: .nothingSelected(fieldText: ""), kind: .chromium, policy: .allowed, expected: true),
    Case(
      failure: .nothingSelected(fieldText: ""), kind: .electron, policy: .allowed, expected: true),
    Case(
      failure: .nothingSelected(fieldText: ""), kind: .electron, policy: .never, expected: false),
    Case(failure: .secureField, kind: .native, policy: .allowed, expected: false),
    Case(failure: .secureField, kind: .chromium, policy: .allowed, expected: false),
    Case(failure: .noAccessibilityPermission, kind: .native, policy: .allowed, expected: false),
    Case(failure: .ownApp, kind: .ownApp, policy: .allowed, expected: false),
  ]

  @Test(arguments: cases) func decides(_ c: Case) {
    #expect(needsCopyFallback(after: c.failure, kind: c.kind, policy: c.policy) == c.expected)
  }
}

struct WholeLineCopyTests {
  @Test func copyOfAWholeLineOfTheFieldIsDiscarded() {
    #expect(isWholeLineCopy("second line\n", fieldText: "first line\nsecond line\nthird"))
    #expect(isWholeLineCopy("third", fieldText: "first line\nsecond line\nthird"))
    #expect(isWholeLineCopy("first line\r\n", fieldText: "first line\r\nsecond"))
  }

  @Test func partialTextIsKept() {
    #expect(!isWholeLineCopy("second", fieldText: "first line\nsecond line\nthird"))
    #expect(!isWholeLineCopy("", fieldText: "first line"))
  }

  @Test func withoutTheFieldOnlyASingleLineEndingInANewlineIsDiscarded() {
    #expect(isWholeLineCopy("let x = 1\n", fieldText: nil))
    #expect(!isWholeLineCopy("let x = 1", fieldText: nil))
    #expect(!isWholeLineCopy("one\ntwo\n", fieldText: nil))
  }
}

/// Drives `CopyFallback` with fake menu, key and permission hooks against a private pasteboard.
@MainActor
final class FallbackHarness {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("au.ibra.dict.tests.\(UUID().uuidString)"))
  var menu: MenuCopyState = .enabled
  var pressError: Int32?
  var postAllowed = true
  var secureInputFailure: CaptureFailure?
  /// What the target puts on the clipboard when asked to copy; nil copies nothing.
  var copies: String? = "copied text"
  var events: [String] = []

  init() {
    pasteboard.clearContents()
    pasteboard.setString("user clipboard", forType: .string)
  }

  func copy() {
    guard let copies else { return }
    pasteboard.clearContents()
    pasteboard.setString(copies, forType: .string)
  }

  var fallback: CopyFallback {
    CopyFallback(
      clipboard: ClipboardGateway(pasteboard: pasteboard),
      findMenuCopy: {
        self.events.append("find")
        return self.menu
      },
      pressMenuCopy: {
        self.events.append("press")
        if let error = self.pressError { return error }
        self.copy()
        return nil
      },
      canPostEvents: { self.postAllowed },
      secureInputBlock: { self.secureInputFailure },
      postCopyKey: {
        self.events.append("key")
        self.copy()
      },
      copyTimeout: .milliseconds(60), lateCopyWindow: .milliseconds(20))
  }

  func run(_ first: CaptureFailure = .unreadable(axError: -25212)) async -> Result<
    CopiedSelection, CaptureFailure
  > {
    await fallback.run(after: first)
  }
}

@MainActor
struct CopyFallbackTests {
  @Test func pressesTheMenuItemAndRestoresTheClipboard() async {
    let h = FallbackHarness()
    let result = await h.run()
    #expect(result == .success(CopiedSelection(text: "copied text", source: .menuCopy)))
    #expect(h.events == ["find", "press"])
    #expect(h.pasteboard.string(forType: .string) == "user clipboard")
  }

  @Test func disabledMenuItemMeansNothingSelectedWithoutAnyKey() async {
    let h = FallbackHarness()
    h.menu = .disabled
    let result = await h.run(.nothingSelected(fieldText: "abc"))
    #expect(result == .failure(.nothingSelected(fieldText: "abc")))
    #expect(h.events == ["find"])
  }

  @Test func missingMenuItemFallsBackToTheKey() async {
    let h = FallbackHarness()
    h.menu = .notFound
    let result = await h.run()
    #expect(result == .success(CopiedSelection(text: "copied text", source: .keyCopy)))
    #expect(h.events == ["find", "key"])
    #expect(h.pasteboard.string(forType: .string) == "user clipboard")
  }

  @Test func failedPressFallsBackToTheKey() async {
    let h = FallbackHarness()
    h.pressError = -25204
    let result = await h.run()
    #expect(result == .success(CopiedSelection(text: "copied text", source: .keyCopy)))
    #expect(h.events == ["find", "press", "key"])
  }

  @Test func keyNeedsPostEventPermission() async {
    let h = FallbackHarness()
    h.menu = .notFound
    h.postAllowed = false
    let result = await h.run()
    #expect(result == .failure(.noPostEventPermission))
    #expect(h.events == ["find"])
  }

  @Test func keyIsNeverPostedIntoASecureInputHolder() async {
    let h = FallbackHarness()
    h.menu = .notFound
    h.secureInputFailure = .secureInput(holder: "Terminal")
    let result = await h.run()
    #expect(result == .failure(.secureInput(holder: "Terminal")))
    #expect(h.events == ["find"])
  }

  @Test func deniedClipboardStopsBeforeAnything() async {
    let h = FallbackHarness()
    let fallback = h.fallback
    let result = await fallback.run(after: .unreadable(axError: nil), accessDenied: true)
    #expect(result == .failure(.clipboardDenied))
    #expect(h.events.isEmpty)
  }

  @Test func timeoutKeepsTheFirstFailureAndTheClipboard() async {
    let h = FallbackHarness()
    h.copies = nil
    let result = await h.run(.unreadable(axError: -25212))
    #expect(result == .failure(.unreadable(axError: -25212)))
    #expect(h.pasteboard.string(forType: .string) == "user clipboard")
  }

  @Test func wholeLineCopyIsDiscarded() async {
    let h = FallbackHarness()
    h.copies = "second line\n"
    let result = await h.run(.nothingSelected(fieldText: "first\nsecond line\n"))
    #expect(result == .failure(.nothingSelected(fieldText: "first\nsecond line\n")))
    #expect(h.pasteboard.string(forType: .string) == "user clipboard")
  }

  @Test func whitespaceOnlyCopyIsNothingSelected() async {
    let h = FallbackHarness()
    h.copies = "  \n"
    let result = await h.run(.nothingSelected(fieldText: nil))
    #expect(result == .failure(.nothingSelected(fieldText: nil)))
  }
}

struct KeyCodeLookupTests {
  @Test func findsTheKeyThatTypesTheCharacter() {
    let layout: [UInt16: String] = [0: "a", 8: "j", 34: "c"]
    #expect(keyCode(typing: "c", translate: { layout[$0] }) == 34)
  }

  @Test func fallsBackToTheANSIKeyWhenNoKeyTypesIt() {
    #expect(keyCode(typing: "c", translate: { _ in nil }) == 8)
  }
}

struct SecureInputTests {
  @Test func blocksKeysOnlyIntoTheHolder() {
    let held = SecureInputState(enabled: true, holderPID: 42)
    #expect(blocksKeyPosting(held, targetPID: 42, kind: .native))
    #expect(!blocksKeyPosting(held, targetPID: 7, kind: .native))
    #expect(
      !blocksKeyPosting(
        SecureInputState(enabled: false, holderPID: 42), targetPID: 42, kind: .native))
  }

  @Test func unknownHolderBlocksOnlyTerminals() {
    let unknown = SecureInputState(enabled: true, holderPID: nil)
    #expect(blocksKeyPosting(unknown, targetPID: 7, kind: .terminal))
    #expect(!blocksKeyPosting(unknown, targetPID: 7, kind: .native))
  }
}

struct WarmupTests {
  @Test func picksTheAttributeForEachKind() {
    let both = AccessibilitySupport(chromium: true, electron: true)
    #expect(warmupAttribute(for: .chromium, support: both) == "AXEnhancedUserInterface")
    #expect(warmupAttribute(for: .electron, support: both) == "AXManualAccessibility")
    #expect(warmupAttribute(for: .native, support: both) == nil)
    #expect(warmupAttribute(for: .terminal, support: both) == nil)
    #expect(warmupAttribute(for: .ownApp, support: both) == nil)
  }

  @Test func respectsTheSwitches() {
    let none = AccessibilitySupport(chromium: false, electron: false)
    #expect(warmupAttribute(for: .chromium, support: none) == nil)
    #expect(warmupAttribute(for: .electron, support: none) == nil)
  }

  @Test func defaultsFollowTheDocumentedSuggestion() {
    let defaults = UserDefaults(suiteName: "au.ibra.dict.tests.\(UUID().uuidString)")
    let support = defaults.map(AccessibilitySupport.init(defaults:))
    #expect(support == AccessibilitySupport(chromium: true, electron: false))
  }
}
