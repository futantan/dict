// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The colour family of a pill, a tinted block or a notice's icon disc.
enum Tone {
  case accent, success, warning, neutral

  /// Behind the content.
  var tint: Color {
    switch self {
    case .accent: Color(Palette.accentTint)
    case .success: Color(Palette.successTint)
    case .warning: Color(Palette.warningTint)
    case .neutral: Color(Palette.neutralTint)
    }
  }

  /// The text and icons on `tint`.
  var onTint: Color {
    switch self {
    case .accent: Color(Palette.accentOnTint)
    case .success: Color(Palette.successOnTint)
    case .warning: Color(Palette.warningOnTint)
    case .neutral: Color(Palette.neutralOnTint)
    }
  }

  /// Behind a block, which is larger than a pill and so lighter for the accent.
  var blockTint: Color { self == .accent ? Color(Palette.accentBlock) : tint }
}

/// A short status on a capsule: the encounters, the proofread's summary, 「未完成」.
struct Pill: View {
  enum Scale { case regular, small }

  let text: String
  var symbol: String?
  var tone = Tone.accent
  var size = Scale.regular
  /// A spinner in place of the symbol, for work in progress.
  var isBusy = false

  init(
    _ text: String, symbol: String? = nil, tone: Tone = .accent, size: Scale = .regular,
    isBusy: Bool = false
  ) {
    self.text = text
    self.symbol = symbol
    self.tone = tone
    self.size = size
    self.isBusy = isBusy
  }

  var body: some View {
    let style = size == .regular ? Typography.pill : Typography.caption
    HStack(spacing: 5) {
      if isBusy {
        Spinner(size: style.size)
      } else if let symbol {
        Image(systemName: symbol).accessibilityHidden(true)
      }
      Text(text).lineLimit(1)
    }
    .font(style.font)
    .foregroundStyle(tone.onTint)
    .padding(.horizontal, size == .regular ? 10 : 7)
    .padding(.vertical, size == .regular ? 3 : 2)
    .background(tone.tint, in: Capsule())
    .fixedSize()
  }
}

/// An icon-only button. Its tooltip and accessibility label are the title and, if it has
/// one, the shortcut: 「复制 ⌘C」.
struct IconButton: View {
  let title: String
  let symbol: String
  var shortcut: String?
  /// The icon in the accent colour, for an action that is on, such as a word marked to learn.
  var isOn = false
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    let label = [title, shortcut].compactMap(\.self).joined(separator: " ")
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: Size.symbol, weight: Size.symbolWeight))
        .frame(width: Size.icon, height: Size.icon)
        .foregroundStyle(isOn ? Color(Palette.accent) : Color(Palette.icon))
        .opacity(isEnabled ? 1 : Size.disabledOpacity)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(
          isHovered && isEnabled ? Color(Palette.iconHover) : .clear,
          in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(label)
    .accessibilityLabel(label)
  }
}

/// The main action: a filled accent capsule with its key cap, 「替换 ↩」. It binds no key
/// itself; the panel or the caller does (`keyboardShortcut(.defaultAction)` on a notice).
struct PrimaryButton: View {
  let title: String
  var symbol: String?
  /// The shortcut printed on the key cap, as menus print it: "↩", "⌘S".
  var keys: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      CapsuleLabel(title: title, symbol: symbol, keys: keys, onFill: true)
        .foregroundStyle(.white)
        .background(Color(Palette.accentFill), in: Capsule())
    }
    .buttonStyle(PressableStyle())
    .accessibilityLabel(title)
  }
}

/// Any other button with a title: a capsule as tall as the primary one, neutral or tinted
/// (「查这个词」), or, compact, an accent-tinted one that sits inside a note.
struct SecondaryButton: View {
  let title: String
  var symbol: String?
  var keys: String?
  /// The full-height capsule's colour; a compact one is always the accent's.
  var tone = Tone.neutral
  var isCompact = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if isCompact {
        Text(title)
          .font(Typography.pill.font)
          .foregroundStyle(Tone.accent.onTint)
          .padding(.horizontal, 11)
          .frame(height: Size.compactButton)
          // On the fill first, so the tint reads the same on a tinted note.
          .background(Tone.accent.tint, in: Capsule())
          .background(Color(Palette.panelFill), in: Capsule())
          .fixedSize()
      } else {
        CapsuleLabel(title: title, symbol: symbol, keys: keys, onFill: false)
          .foregroundStyle(tone == .neutral ? Color(Palette.textPrimary) : tone.onTint)
          .background(tone.tint, in: Capsule())
      }
    }
    .buttonStyle(PressableStyle())
    .accessibilityLabel(title)
  }
}

/// The title, symbol and key cap of a full-height capsule button.
private struct CapsuleLabel: View {
  let title: String
  let symbol: String?
  let keys: String?
  /// On the accent fill, where the key cap is white and translucent.
  let onFill: Bool

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        if let symbol {
          Image(systemName: symbol).accessibilityHidden(true)
        }
        Text(title).lineLimit(1)
      }
      if let keys {
        Text(keys)
          .font(Typography.caption.font)
          .padding(.horizontal, 4)
          .frame(minWidth: Size.keycap, minHeight: Size.keycap)
          .background(
            onFill
              ? Color.white.opacity(Size.keycapOnFill)
              : Color(Palette.textPrimary).opacity(Size.keycapOnTint),
            in: RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
          )
          .accessibilityHidden(true)
      }
    }
    .font(Typography.button.font)
    // The key cap sits as far from the end as from the top and bottom.
    .padding(.leading, symbol == nil ? 14 : 12)
    .padding(.trailing, keys == nil ? 14 : (Size.button - Size.keycap) / 2)
    .frame(height: Size.button)
    .fixedSize()
    .contentShape(Capsule())
  }
}

/// Dims a button while it is pressed.
private struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
  }
}

/// A block that stands out on a light tint, with an optional small heading in its colour:
/// 「本句」, the back-translation.
struct TintedBlock<Content: View>: View {
  var label: String?
  var tone = Tone.accent
  @ViewBuilder let content: Content

  init(label: String? = nil, tone: Tone = .accent, @ViewBuilder content: () -> Content) {
    self.label = label
    self.tone = tone
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let label {
        Text(label)
          .font(Typography.label.font)
          .foregroundStyle(tone.onTint)
      }
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Spacing.blockVertical)
    .padding(.horizontal, Spacing.blockHorizontal)
    .background(
      tone.blockTint, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
  }
}

/// The bar along the bottom of the panel: a status pill on the left, then the icon
/// buttons, then the primary button at the trailing edge.
struct BottomBar<Status: View, Icons: View, Primary: View>: View {
  @ViewBuilder let status: Status
  @ViewBuilder let icons: Icons
  @ViewBuilder let primary: Primary

  var body: some View {
    HStack(spacing: Spacing.buttons) {
      status
      Spacer(minLength: 0)
      HStack(spacing: Spacing.iconButtons) { icons }
      primary
    }
    .frame(minHeight: Size.iconButton)
    .padding(.top, Spacing.barTop)
  }
}

extension BottomBar where Primary == EmptyView {
  init(@ViewBuilder status: () -> Status, @ViewBuilder icons: () -> Icons) {
    self.init(status: status, icons: icons, primary: { EmptyView() })
  }
}

/// A thin line between the original and the result.
struct Hairline: View {
  var body: some View {
    Rectangle()
      .fill(Color(Palette.separator))
      .frame(height: 0.5)
      .accessibilityHidden(true)
  }
}

/// An accent arc turning on a lighter ring.
struct Spinner: View {
  var size = Size.spinner
  @State private var isTurning = false

  var body: some View {
    let line = size / 7
    ZStack {
      Circle().stroke(Color(Palette.spinnerTrack), lineWidth: line)
      Circle()
        .trim(from: 0, to: 0.25)
        .stroke(Color(Palette.accent), style: StrokeStyle(lineWidth: line, lineCap: .round))
        .rotationEffect(.degrees(isTurning ? 360 : 0))
    }
    .padding(line / 2)
    .frame(width: size, height: size)
    .onAppear {
      withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
        isTurning = true
      }
    }
  }
}
