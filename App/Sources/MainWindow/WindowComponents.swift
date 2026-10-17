// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The main window's shared pieces (Design/main-app/*.html), built from `WindowTheme` and
/// the panel's components.

/// A page's title, with an optional line above it: 「10 月 17 日 星期六」 / 「今天」.
struct PageHeader: View {
  let title: String
  var subtitle: String?

  var body: some View {
    VStack(alignment: .leading, spacing: WindowLayout.titleSpacing) {
      if let subtitle {
        Text(subtitle)
          .font(WindowType.pageSubtitle.font)
          .foregroundStyle(Color(Palette.textSecondary))
      }
      Text(title)
        .font(WindowType.pageTitle.font)
        .tracking(WindowType.pageTitle.tracking)
        .foregroundStyle(Color(Palette.textPrimary))
        .accessibilityAddTraits(.isHeader)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A heading above a card, with an optional trailing link: 「最近查询 · 全部记录 ›」.
struct SectionHeading<Trailing: View>: View {
  let title: String
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(WindowType.heading.font)
        .foregroundStyle(Color(Palette.textPrimary))
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: Spacing.row)
      trailing
    }
  }
}

extension SectionHeading where Trailing == EmptyView {
  init(_ title: String) {
    self.init(title: title, trailing: { EmptyView() })
  }
}

/// A link-coloured text button: 「全部记录 ›」.
struct LinkButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(Typography.secondary.font)
        .foregroundStyle(Color(Palette.accent))
    }
    .buttonStyle(.plain)
  }
}

/// A white rounded card with a hairline edge; its rows are separated by `CardDivider`.
struct WindowCard<Content: View>: View {
  var padding: CGFloat = 0
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(Palette.cardFill),
        in: RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
          .strokeBorder(Color(Palette.separator), lineWidth: 0.5)
      )
  }
}

/// The line between two rows of a card, from edge to edge.
struct CardDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(Palette.rowSeparator))
      .frame(height: 0.5)
      .accessibilityHidden(true)
  }
}

/// A row of a settings card: a title with an optional explanation, and its control.
struct SettingsRow<Control: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: Spacing.input) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(WindowType.row.font)
          .foregroundStyle(Color(Palette.textPrimary))
        if let subtitle {
          Text(subtitle)
            .font(WindowType.footnote.font)
            .foregroundStyle(Color(Palette.textSecondary))
            .lineSpacing(WindowType.footnote.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      control
    }
    .padding(.horizontal, WindowLayout.cardRowHorizontal)
    .padding(.vertical, subtitle == nil ? 0 : WindowLayout.cardRowVertical - 2)
    .frame(minHeight: WindowLayout.rowMinHeight)
  }
}

/// A settings row whose control is a switch.
struct SwitchRow: View {
  let title: String
  var subtitle: String?
  @Binding var isOn: Bool

  var body: some View {
    SettingsRow(title: title, subtitle: subtitle) {
      Toggle(title, isOn: $isOn)
        .toggleStyle(.switch)
        .labelsHidden()
    }
  }
}

/// A sidebar item: icon, title, and a count or a badge after it.
struct SidebarItem: View {
  let section: MainSection
  let isSelected: Bool
  /// Plain after the title: 生词本's count.
  var count: Int?
  /// On an accent capsule: 复习's due count; hidden at 0.
  var badge: Int?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: WindowLayout.sidebarItemPadding) {
        Image(systemName: section.symbol)
          .font(.system(size: Size.symbol, weight: Size.symbolWeight))
          .frame(width: Size.icon, height: Size.icon)
          .accessibilityHidden(true)
        Text(section.title)
          .font((isSelected ? WindowType.sidebarItemSelected : WindowType.sidebarItem).font)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let count, count > 0 {
          Text(count, format: .number)
            .font(WindowType.detail.font)
            .foregroundStyle(Color(Palette.textSecondary))
        }
        if let badge, badge > 0 {
          Text(badge, format: .number)
            .font(WindowType.badge.font)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Color(Palette.accentFill), in: Capsule())
        }
      }
      .foregroundStyle(isSelected ? Color(Palette.accentOnTint) : Color(Palette.textQuiet))
      .padding(.horizontal, WindowLayout.sidebarItemPadding)
      .frame(height: WindowLayout.sidebarItemHeight)
      .background(
        isSelected ? Color(Palette.accentTint) : .clear,
        in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// A key cap on the neutral tint: 「⌘K」, 「⌥A」.
struct KeyCap: View {
  let keys: String

  var body: some View {
    Text(keys)
      .font(Typography.caption.font)
      .foregroundStyle(Color(Palette.icon))
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(
        Color(Palette.neutralTint),
        in: RoundedRectangle(cornerRadius: Radius.keycap - 1, style: .continuous))
  }
}

/// One figure of 今日概况: a label, a big number and its unit.
struct StatTile<Accessory: View>: View {
  let label: String
  let value: Int
  let unit: String
  /// The accent block with the label in the accent: 待复习.
  var isEmphasized = false
  @ViewBuilder let accessory: Accessory

  var body: some View {
    HStack(spacing: Spacing.pill) {
      VStack(alignment: .leading, spacing: 6) {
        Text(label)
          .font((isEmphasized ? WindowType.statLabelEmphasis : WindowType.statLabel).font)
          .foregroundStyle(
            isEmphasized ? Color(Palette.accentOnTint) : Color(Palette.textSecondary))
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(value, format: .number)
            .font(WindowType.statValue.font)
            .foregroundStyle(Color(Palette.textPrimary))
          Text(unit)
            .font(WindowType.statUnit.font)
            .foregroundStyle(Color(Palette.textSecondary))
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      accessory
    }
    .padding(.vertical, WindowLayout.tileVertical)
    .padding(.horizontal, WindowLayout.tileHorizontal)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      let shape = RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
      if isEmphasized {
        shape.fill(Color(Palette.accentBlock))
      } else {
        shape.fill(Color(Palette.cardFill))
          .overlay(shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5))
      }
    }
  }
}

extension StatTile where Accessory == EmptyView {
  init(label: String, value: Int, unit: String) {
    self.init(label: label, value: value, unit: unit, accessory: { EmptyView() })
  }
}

/// A small capsule button on the neutral tint, as in the mockups' cards: 「要学」, 「导出…」.
/// `.danger` puts it on the red tint: 「清除所有记录…」.
struct CardButton: View {
  enum Role { case normal, danger }

  let title: String
  var role = Role.normal
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(Typography.pill.font)
        .foregroundStyle(role == .danger ? Color(Palette.dangerOnTint) : Color(Palette.textQuiet))
        .padding(.horizontal, WindowLayout.cardButtonPadding)
        .frame(height: WindowLayout.cardButtonHeight)
        .background(
          role == .danger ? Color(Palette.dangerTint) : Color(Palette.neutralTint), in: Capsule()
        )
        .opacity(isEnabled ? 1 : Size.disabledOpacity * 2)
        .fixedSize()
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

extension View {
  /// No blur where a page scrolls under the transparent title bar: the mockups have none,
  /// and macOS 26 draws it over the whole page in an offscreen render.
  func withoutScrollEdgeEffect() -> some View {
    Group {
      if #available(macOS 26, *) {
        scrollEdgeEffectHidden(true, for: .all)
      } else {
        self
      }
    }
  }
}

/// A page: its header fixed in the top margin, then its content scrolling in the page
/// margins. The scroll view starts below the header, so nothing scrolls under the traffic
/// lights; one that reaches the title bar also draws blank offscreen on macOS 26.
struct PageScaffold<Content: View>: View {
  let title: String
  var subtitle: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PageHeader(title: title, subtitle: subtitle)
        .padding(.top, WindowLayout.pageTop)
        .padding(.horizontal, WindowLayout.pageSide)
        .padding(.bottom, WindowLayout.pageSpacing - WindowLayout.shadowRoom)
      ScrollView {
        content
          .padding(.top, WindowLayout.shadowRoom)
          .padding(.horizontal, WindowLayout.pageSide)
          .padding(.bottom, WindowLayout.pageBottom)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }
}
