// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The settings page's app language picker. A new choice shows after a relaunch, which the
/// row offers until the running language matches the choice.
struct InterfaceLanguageRow: View {
  var defaults = UserDefaults.standard

  @State private var chosen: InterfaceLanguage?

  var body: some View {
    let selection = chosen ?? InterfaceLanguage.chosen(in: defaults)
    let needsRelaunch = selection != InterfaceLanguage.running
    SettingsRow(
      title: SettingsText.interfaceLanguage,
      subtitle: needsRelaunch ? SettingsText.interfaceLanguageRelaunch : nil
    ) {
      HStack(spacing: Spacing.buttons) {
        if needsRelaunch {
          CardButton(title: SettingsText.relaunchNow) { InterfaceLanguage.relaunch() }
        }
        Picker(
          SettingsText.interfaceLanguage,
          selection: Binding(
            get: { selection },
            set: { language in
              language.choose(in: defaults)
              chosen = language
            })
        ) {
          // Each in its own language; never localized.
          ForEach(InterfaceLanguage.allCases, id: \.self) { Text(verbatim: $0.name).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
      }
    }
  }
}
