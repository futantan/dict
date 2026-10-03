// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The onboarding step that picks the "read" and "write" shortcuts (architecture 11.4).
/// There are no defaults; the onboarding window (M1.11) moves on once `isComplete` holds.
struct HotkeyStepView: View {
  let center: HotkeyCenter

  static func isComplete(_ center: HotkeyCenter) -> Bool {
    HotkeyRole.allCases.allSatisfy { center.combos[$0] != nil }
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
              "Select text in any app and press a shortcut. Pick combinations you do not use elsewhere, such as ⌃⌥ with a letter.",
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
              Text(role.title).font(.headline)
              Text(role.summary).font(.callout).foregroundStyle(.secondary)
            }
            ShortcutRecorder(role: role, center: center)
          }
        }
      }

      Text(
        String(
          localized: "You can change them later in Settings.", table: "Hotkeys",
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
