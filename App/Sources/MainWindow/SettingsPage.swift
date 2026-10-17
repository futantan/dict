// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// 设置 (Design/main-app/settings.html): a list of sections beside one scrolling column of
/// cards. The settings themselves are `SettingsModel`'s and the shortcut center's, as in
/// the old Settings window; the model section (`ModelSettingsSection`) shares the onboarding's
/// model logic.
struct SettingsPage: View {
  let model: SettingsModel
  let hotkeys: HotkeyCenter
  let data: WindowData
  let navigation: MainNavigation
  let services: SettingsServices

  @State private var selected = SettingsSection.general
  @State private var login = LoginItem.Status.off
  @State private var loginError: String?
  @State private var accessibilityGranted = false
  @State private var isConfirmingClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: WindowLayout.pageSpacing) {
      PageHeader(title: MainSection.settings.title)
        .padding(.horizontal, WindowLayout.pageSide)
        .padding(.top, WindowLayout.pageTop)
      ScrollViewReader { proxy in
        HStack(alignment: .top, spacing: WindowLayout.settingsSpacing) {
          sectionList(proxy)
          ScrollView {
            column
              .padding(.trailing, WindowLayout.pageSide)
              .padding(.bottom, WindowLayout.pageBottom)
          }
          .scrollIndicators(.automatic)
        }
        .padding(.leading, WindowLayout.pageSide)
        .onChange(of: navigation.settingsSection, initial: true) { _, section in
          guard let section else { return }
          select(section, proxy)
          navigation.didScrollToSettingsSection()
        }
      }
    }
    .task(id: data.refreshID) {
      login = services.loginItem.status()
      accessibilityGranted = services.accessibilityGranted()
    }
    .alert(SettingsText.clearTitle, isPresented: $isConfirmingClear) {
      Button(SettingsText.clearConfirm, role: .destructive) {
        Task { await data.deleteAll() }
      }
    } message: {
      Text(SettingsText.clearMessage)
    }
  }

  private func select(_ section: SettingsSection, _ proxy: ScrollViewProxy) {
    selected = section
    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(section, anchor: .top) }
  }

  private func sectionList(_ proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SettingsSection.allCases, id: \.self) { section in
        let isSelected = section == selected
        Button {
          select(section, proxy)
        } label: {
          Text(section.title)
            .font((isSelected ? WindowType.sidebarItemSelected : WindowType.sidebarItem).font)
            .foregroundStyle(Color(isSelected ? Palette.accentOnTint : Palette.textQuiet))
            .padding(.horizontal, Spacing.pill)
            .frame(
              maxWidth: .infinity, minHeight: WindowLayout.settingsItemHeight, alignment: .leading
            )
            .background(
              isSelected ? Color(Palette.accentTint) : .clear,
              in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .frame(width: WindowLayout.settingsListWidth)
  }

  private var column: some View {
    VStack(alignment: .leading, spacing: WindowLayout.pageSpacing) {
      group(.general) { general }
      group(.languages, footnote: SettingsText.languagesNote) { LanguageRows(model: model) }
      ModelSettingsSection(model: model).id(SettingsSection.model)
      group(.shortcuts, footnote: SettingsText.shortcutsNote) { ShortcutRows(center: hotkeys) }
      group(.writing) { writing }
      group(.voice) { voice }
      group(.permissions) { permissions }
      group(.privacy) { privacy }
      group(.about) { about }
    }
    .frame(maxWidth: WindowLayout.settingsColumnMaxWidth, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func group<Content: View>(
    _ section: SettingsSection, footnote: String? = nil, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: WindowLayout.headingSpacing) {
      SectionHeading(section.title)
      WindowCard { content() }
      if let footnote { CardFootnote(text: footnote) }
    }
    .id(section)
  }

  // MARK: General

  @ViewBuilder
  private var general: some View {
    SwitchRow(
      title: SettingsText.launchAtLogin,
      subtitle: loginError ?? (login == .needsApproval ? SettingsText.loginNeedsApproval : nil),
      isOn: Binding(get: { login != .off }, set: { setLogin($0) }))
    CardDivider()
    SwitchRow(
      title: SettingsText.showInDock,
      subtitle: model.preferences.showsMenuBarIcon ? nil : SettingsText.iconsNote,
      isOn: presence(\.showsDockIcon) { $0.setShowsDockIcon($1) }
    )
    .disabled(!model.preferences.showsMenuBarIcon)
    CardDivider()
    SwitchRow(
      title: SettingsText.showInMenuBar,
      subtitle: model.preferences.showsDockIcon ? nil : SettingsText.iconsNote,
      isOn: presence(\.showsMenuBarIcon) { $0.setShowsMenuBarIcon($1) }
    )
    .disabled(!model.preferences.showsDockIcon)
    CardDivider()
    SwitchRow(
      title: SettingsText.keepRunning, subtitle: SettingsText.keepRunningNote,
      isOn: preference(\.keepsRunningAfterClose) { $0.keepsRunningAfterClose = $1 })
  }

  private func setLogin(_ enabled: Bool) {
    do {
      try services.loginItem.setEnabled(enabled)
      loginError = nil
    } catch {
      loginError = error.localizedDescription
      Log.ui.error("launch at login: \(String(describing: error), privacy: .public)")
    }
    login = services.loginItem.status()
  }

  private func presence(
    _ keyPath: KeyPath<Preferences, Bool>, set: @escaping (inout Preferences, Bool) -> Void
  ) -> Binding<Bool> {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in
        model.update { set(&$0, value) }
        services.presenceChanged(model.preferences)
      })
  }

  private func preference<Value>(
    _ keyPath: KeyPath<Preferences, Value>, set: @escaping (inout Preferences, Value) -> Void
  ) -> Binding<Value> {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in model.update { set(&$0, value) } })
  }

  // MARK: Writing

  private var writing: some View {
    SwitchRow(
      title: SettingsText.keepFormatting, subtitle: SettingsText.keepFormattingNote,
      isOn: preference(\.keepsFormatting) { $0.keepsFormatting = $1 })
  }

  // MARK: Voice

  private var voice: some View {
    let language = model.preferences.languagePair.learning
    let choice = services.voice()
    let name = SettingsText.languageName(model.preferences.learningLanguage)
    return SettingsRow(
      title: choice.voice.map { SettingsText.voice(language: name, name: $0.name) }
        ?? SettingsText.noVoice,
      subtitle: SpeechStrings.hint(choice.hint) ?? SettingsText.voiceIsGood
    ) {
      if choice.hint != nil {
        CardButton(title: SpeechStrings.manageVoices, action: services.openVoiceSettings)
      }
    }
    .id(language.minimalIdentifier)
  }

  // MARK: Permissions

  private var permissions: some View {
    SettingsRow(title: SettingsText.accessibility, subtitle: SettingsText.accessibilityNote) {
      HStack(spacing: Spacing.buttons) {
        Pill(
          accessibilityGranted ? SettingsText.permissionOn : SettingsText.permissionOff,
          symbol: accessibilityGranted ? "checkmark.circle" : "exclamationmark.triangle",
          tone: accessibilityGranted ? .success : .warning)
        CardButton(
          title: SettingsText.openSystemSettings, action: services.openAccessibilitySettings)
      }
    }
  }

  // MARK: Data and privacy

  @ViewBuilder
  private var privacy: some View {
    HStack(alignment: .top, spacing: Spacing.row) {
      Image(systemName: "lock")
        .font(.system(size: Size.symbol, weight: Size.symbolWeight))
        .foregroundStyle(Color(Palette.successOnTint))
        .frame(width: Size.icon, height: Size.icon)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(SettingsText.recordsStayHere)
          .font(WindowType.row.font)
          .foregroundStyle(Color(Palette.textPrimary))
        Text(
          SettingsText.recordsCount(terms: data.totals.terms, sentences: data.totals.sentences)
        )
        .font(WindowType.footnote.font)
        .foregroundStyle(Color(Palette.textSecondary))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, WindowLayout.cardRowVertical + 2)
    CardDivider()
    SettingsRow(title: SettingsText.exportRecords, subtitle: SettingsText.exportNote) {
      CardButton(title: SettingsText.exportButton, action: services.export)
        .disabled(!data.isAvailable)
    }
    CardDivider()
    SettingsRow(title: SettingsText.clearRecords) {
      CardButton(title: SettingsText.clearButton, role: .danger) { isConfirmingClear = true }
        .disabled(!data.isAvailable)
    }
  }

  // MARK: About

  private var about: some View {
    SettingsRow(
      title: SettingsText.appVersion(services.appName, services.version),
      subtitle: services.checkForUpdates == nil
        ? SettingsText.updatesOff : SettingsText.updatesOn
    ) {
      if let check = services.checkForUpdates {
        CardButton(title: SettingsText.checkForUpdates, action: check)
          .disabled(!services.canCheckForUpdates())
      }
    }
  }
}

/// The language pickers of the settings page.
struct LanguageRows: View {
  let model: SettingsModel

  var body: some View {
    SettingsRow(title: SettingsText.myLanguage) {
      languagePicker(SettingsText.myLanguage, binding(\.myLanguage) { $0.setMyLanguage($1) })
    }
    CardDivider()
    SettingsRow(title: SettingsText.learningLanguage) {
      languagePicker(
        SettingsText.learningLanguage, binding(\.learningLanguage) { $0.setLearningLanguage($1) })
    }
    if model.preferences.learningLanguage == "en" {
      CardDivider()
      SettingsRow(title: SettingsText.accent) {
        Picker(SettingsText.accent, selection: binding(\.accent) { $0.accent = $1 }) {
          ForEach(Accent.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .settingsMenu()
      }
    }
  }

  private func languagePicker(_ title: String, _ selection: Binding<String>) -> some View {
    Picker(title, selection: selection) {
      ForEach(Preferences.languages, id: \.self) { Text(SettingsText.languageName($0)).tag($0) }
    }
    .settingsMenu()
  }

  private func binding<Value>(
    _ keyPath: KeyPath<Preferences, Value>, set: @escaping (inout Preferences, Value) -> Void
  ) -> Binding<Value> {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in model.update { set(&$0, value) } })
  }
}

/// The shortcut recorders of the settings page, recording into the app's registered center.
struct ShortcutRows: View {
  let center: HotkeyCenter

  var body: some View {
    ForEach(Array(HotkeyRole.allCases.enumerated()), id: \.element) { index, role in
      if index > 0 { CardDivider() }
      SettingsRow(title: role.title, subtitle: role.summary) {
        ShortcutRecorder(role: role, center: center)
      }
    }
  }
}

/// A note under a card.
struct CardFootnote: View {
  let text: String

  var body: some View {
    Text(text)
      .font(WindowType.footnote.font)
      .lineSpacing(WindowType.footnote.lineSpacing)
      .foregroundStyle(Color(Palette.textSecondary))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 4)
  }
}

extension View {
  /// A pop-up menu without its label, as the settings rows show them.
  fileprivate func settingsMenu() -> some View {
    labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
  }
}
