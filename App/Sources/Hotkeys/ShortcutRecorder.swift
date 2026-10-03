// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records the combination for one role. Click, then press the keys; Esc cancels and
/// Delete clears. Used by the onboarding step and by Settings.
struct ShortcutRecorder: View {
  let role: HotkeyRole
  let center: HotkeyCenter

  @State private var isRecording = false
  @State private var heldModifiers: KeyCombo.Modifiers = []
  @State private var rejection: HotkeyProblem?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Button(action: toggleRecording) {
          Text(label)
            .monospacedDigit()
            .foregroundStyle(isRecording || center.combos[role] == nil ? .secondary : .primary)
            .frame(minWidth: 140)
        }
        .background(
          KeyCaptureView(
            isActive: isRecording,
            onModifiers: { heldModifiers = $0 },
            onKey: finish,
            onClear: {
              stopRecording(); center.clear(role)
            },
            onCancel: stopRecording)
        )
        .accessibilityLabel(Text(role.title))
        .accessibilityValue(Text(label))

        if center.combos[role] != nil && !isRecording {
          Button {
            rejection = nil
            center.clear(role)
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless)
          .help(
            String(
              localized: "Remove shortcut", table: "Hotkeys",
              comment: "Help tag of the button that removes a shortcut"))
        }
      }
      if let problem = rejection ?? center.problems[role] {
        Text(problem.message)
          .font(.callout)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onDisappear { if isRecording { stopRecording() } }
  }

  private var label: String {
    if isRecording {
      return heldModifiers.isEmpty
        ? String(
          localized: "Press keys…", table: "Hotkeys",
          comment: "Shown in the shortcut field while waiting for a key press")
        : HotkeyRules.displayString(KeyCombo(keyCode: 0, modifiers: heldModifiers), keyName: "")
    }
    guard let combo = center.combos[role] else {
      return String(
        localized: "Record Shortcut", table: "Hotkeys",
        comment: "Shortcut field with no shortcut; clicking it starts recording")
    }
    return center.displayString(combo)
  }

  private func toggleRecording() {
    if isRecording {
      stopRecording()
    } else {
      rejection = nil
      heldModifiers = []
      center.isPaused = true
      isRecording = true
    }
  }

  private func stopRecording() {
    isRecording = false
    heldModifiers = []
    center.isPaused = false
  }

  private func finish(_ combo: KeyCombo) {
    stopRecording()
    rejection = center.assign(combo, to: role)
  }
}

/// An invisible view that takes keyboard focus while recording and reports key presses,
/// including ones that would otherwise be menu key equivalents.
private struct KeyCaptureView: NSViewRepresentable {
  let isActive: Bool
  let onModifiers: (KeyCombo.Modifiers) -> Void
  let onKey: (KeyCombo) -> Void
  let onClear: () -> Void
  let onCancel: () -> Void

  func makeNSView(context: Context) -> CaptureView { CaptureView() }

  func updateNSView(_ view: CaptureView, context: Context) {
    view.handlers = self
    guard isActive != view.isActive else { return }
    view.isActive = isActive
    if isActive {
      // Wait for the button click to finish, or it takes focus back.
      Task { view.window?.makeFirstResponder(view) }
    } else if view.window?.firstResponder === view {
      view.window?.makeFirstResponder(nil)
    }
  }

  final class CaptureView: NSView {
    var handlers: KeyCaptureView?
    var isActive = false

    override var acceptsFirstResponder: Bool { isActive }

    override func resignFirstResponder() -> Bool {
      if isActive { handlers?.onCancel() }
      return true
    }

    override func flagsChanged(with event: NSEvent) {
      handlers?.onModifiers(KeyCombo.Modifiers(event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard isActive, window?.firstResponder === self else {
        return super.performKeyEquivalent(with: event)
      }
      keyDown(with: event)
      return true
    }

    override func keyDown(with event: NSEvent) {
      guard isActive, !event.isARepeat else { return }
      let modifiers = KeyCombo.Modifiers(event.modifierFlags)
      switch (Int(event.keyCode), modifiers.isEmpty) {
      case (kVK_Escape, true): handlers?.onCancel()
      case (kVK_Delete, true), (kVK_ForwardDelete, true): handlers?.onClear()
      default: handlers?.onKey(KeyCombo(keyCode: event.keyCode, modifiers: modifiers))
      }
    }
  }
}
