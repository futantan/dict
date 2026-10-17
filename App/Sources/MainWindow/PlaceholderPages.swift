// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// The pages a later wave builds (Design/main-app/saved.html, review.html).
// Each replaces its struct here with a file of its own, keeping the name and the inputs it
// needs from `MainWindowView.page(for:)`.

struct SavedPage: View {
  let data: WindowData

  var body: some View { PlaceholderPage(section: .saved) }
}

struct ReviewPage: View {
  let data: WindowData

  var body: some View { PlaceholderPage(section: .review) }
}

private struct PlaceholderPage: View {
  let section: MainSection

  var body: some View {
    PageScaffold(title: section.title) {
      Text(WindowStrings.comingSoon)
        .font(WindowType.row.font)
        .foregroundStyle(Color(Palette.textSecondary))
    }
  }
}
