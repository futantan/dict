// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The onboarding step that picks the "read" and "write" shortcuts (architecture 11.4).
/// There are no defaults. Only "read" is required: "write" has no action until writing help
/// exists, so the onboarding window moves on once `isComplete` holds.
struct HotkeyStepView: View {
  let center: HotkeyCenter

  static func isComplete(_ center: HotkeyCenter) -> Bool {
    center.shortcuts[.read] != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          String(
            localized: "Choose your shortcuts", table: "Hotkeys",
            comment: "Title of the onboarding step that picks the two shortcuts")
        )
        .font(.title2.bold())
        Text(
          String(
            localized:
              "Select text in any app and press a shortcut. Pick one you do not use elsewhere, such as ⌃⌥ with a letter, or press a modifier key such as ⌥ twice.",
            table: "Hotkeys",
            comment: "Explanation in the onboarding step that picks the two shortcuts")
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
        ForEach(HotkeyRole.allCases, id: \.self) { role in
          GridRow {
            VStack(alignment: .leading, spacing: 2) {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(role.title).font(.headline)
                if role == .write {
                  Text(
                    String(
                      localized: "Optional", table: "Hotkeys",
                      comment: "Next to the Write shortcut in onboarding: it can be left empty")
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
              }
              Text(role.summary).font(.callout).foregroundStyle(.secondary)
            }
            ShortcutRecorder(role: role, center: center)
          }
        }
      }

      Text(
        String(
          localized: "Only Read is needed to start. You can change both later in Settings.",
          table: "Hotkeys",
          comment: "Footnote in the onboarding step that picks the two shortcuts")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(maxWidth: 560, alignment: .leading)
  }
}

#Preview {
  HotkeyStepView(
    center: HotkeyCenter(defaults: UserDefaults(suiteName: "HotkeyStepPreview") ?? .standard))
}
