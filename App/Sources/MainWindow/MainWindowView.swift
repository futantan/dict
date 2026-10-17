// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Everything the window's pages share; built once by the window controller.
@MainActor
struct MainWindowContext {
  let navigation: MainNavigation
  let data: WindowData
  let settings: SettingsModel
  let hotkeys: HotkeyCenter
  let services: SettingsServices
  /// The Today page's search: the text and the field's rect in the window's content.
  let lookUp: (String, CGRect) -> Void
}

/// The window's root: the fixed sidebar and the selected page (Design/main-app/README.md).
struct MainWindowView: View {
  let context: MainWindowContext

  var body: some View {
    HStack(spacing: 0) {
      Sidebar(context: context)
      Rectangle()
        .fill(Color(Palette.separator))
        .frame(width: 0.5)
        .accessibilityHidden(true)
      page(for: context.navigation.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(Palette.panelFill))
    }
    .withoutScrollEdgeEffect()
    .ignoresSafeArea()
    .background {
      // ⌘K from any page: the search field on Today.
      Button("") { context.navigation.focusSearch() }
        .keyboardShortcut("k", modifiers: .command)
        .hidden()
    }
  }

  /// One view per section; a new page replaces its placeholder here.
  @ViewBuilder
  private func page(for section: MainSection) -> some View {
    switch section {
    case .today:
      TodayPage(data: context.data, navigation: context.navigation, lookUp: context.lookUp)
    case .history: HistoryPage(data: context.data)
    case .saved: SavedPage(data: context.data)
    case .review: ReviewPage(data: context.data)
    case .settings:
      SettingsPage(
        model: context.settings, hotkeys: context.hotkeys, data: context.data,
        navigation: context.navigation, services: context.services)
    }
  }

}

/// The sidebar: the sections, then 设置 and the shortcut card at the bottom.
private struct Sidebar: View {
  let context: MainWindowContext

  var body: some View {
    let navigation = context.navigation
    VStack(alignment: .leading, spacing: WindowLayout.sidebarItemSpacing) {
      ForEach([MainSection.today, .history, .saved, .review], id: \.self) { section in
        item(section)
      }
      Spacer(minLength: 0)
      item(.settings)
      ShortcutCard(hotkeys: context.hotkeys)
        .padding(.top, WindowLayout.sidebarItemSpacing * 2.5)
    }
    .padding(.top, WindowLayout.sidebarTop)
    .padding(.horizontal, WindowLayout.sidebarSide)
    .padding(.bottom, WindowLayout.sidebarBottom)
    .frame(width: WindowLayout.sidebarWidth)
    .frame(maxHeight: .infinity)
    .background(Color(Palette.sidebarFill))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(navigation.section.title)
  }

  private func item(_ section: MainSection) -> some View {
    SidebarItem(
      section: section, isSelected: context.navigation.section == section,
      count: section == .saved ? context.data.learningCount : nil,
      badge: section == .review ? context.data.dueCount : nil
    ) {
      context.navigation.section = section
    }
  }
}

/// The two shortcuts at the bottom of the sidebar.
private struct ShortcutCard: View {
  let hotkeys: HotkeyCenter

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      row(WindowStrings.readShortcut, role: .read)
      row(WindowStrings.writeShortcut, role: .write)
    }
    .font(WindowType.detail.font)
    .foregroundStyle(Color(Palette.textSecondary))
    .padding(WindowLayout.shortcutCardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(Palette.panelFill),
      in: RoundedRectangle(cornerRadius: WindowLayout.shortcutCardRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WindowLayout.shortcutCardRadius, style: .continuous)
        .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
    )
  }

  private func row(_ title: String, role: HotkeyRole) -> some View {
    HStack {
      Text(title).lineLimit(1)
      Spacer(minLength: Spacing.buttons)
      KeyCap(keys: hotkeys.shortcuts[role].map(hotkeys.displayString) ?? WindowStrings.noShortcut)
    }
  }
}
