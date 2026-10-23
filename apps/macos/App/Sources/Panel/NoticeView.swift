// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A failure or a missing permission or model: the icon on a tinted disc, the title and the
/// message beside it, the buttons at the bottom right. The default button is the primary
/// one and answers Return.
struct NoticeView: View {
  let notice: PanelNotice
  let defaultSymbol: String
  let tone: Tone
  let onAction: (PanelAction.ID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.section) {
      // A title alone is centred on the disc; with a message it starts at the disc's top.
      HStack(alignment: notice.message == nil ? .center : .top, spacing: Spacing.pill) {
        Image(systemName: notice.symbol ?? defaultSymbol)
          .font(.system(size: Size.symbol, weight: Size.symbolWeight))
          .foregroundStyle(tone.onTint)
          .frame(width: Size.disc, height: Size.disc)
          .background(tone.tint, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Spacing.tight) {
          Text(notice.title)
            .font(Typography.title.font)
            .foregroundStyle(Color(Palette.textPrimary))
          if let message = notice.message {
            Text(message)
              .font(Typography.secondary.font)
              .foregroundStyle(Color(Palette.textSecondary))
              .lineSpacing(Typography.secondary.lineSpacing)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      }
      if !notice.actions.isEmpty {
        HStack(spacing: Spacing.buttons) {
          Spacer(minLength: 0)
          ForEach(notice.actions) { action in
            if action.isDefault {
              PrimaryButton(title: action.title, keys: "↩") { onAction(action.id) }
                .keyboardShortcut(.defaultAction)
            } else {
              SecondaryButton(title: action.title) { onAction(action.id) }
            }
          }
        }
        .padding(.top, Spacing.barTop)
      }
    }
  }
}
