// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The small note shown after a replacement (architecture 11.3). It never becomes key and
/// never activates Dict, so the app just written into keeps its focus. When it hides is
/// `ToastLifetime`'s call.
@MainActor
final class ToastController {
  static let shared = ToastController()

  private lazy var panel = makePanel()
  private let model = ToastModel()
  private var hideTask: Task<Void, Never>?

  /// Shows `message` under `bounds` (screen coordinates), or at the top of the screen with
  /// the pointer.
  func show(_ message: ToastMessage, near bounds: CGRect?) {
    model.message = message
    model.copied = false
    panel.contentView?.layoutSubtreeIfNeeded()
    let size = panel.contentView?.fittingSize ?? CGSize(width: 280, height: 40)
    panel.setFrame(CGRect(origin: origin(for: size, near: bounds), size: size), display: true)
    panel.orderFrontRegardless()
    Log.ui.info("toast shown: \(message.logName, privacy: .public)")
    model.lifetime.show(at: .now)
    hideTask?.cancel()
    hideTask = Task { [weak self] in
      do {
        try await Task.sleep(for: ToastLifetime.linger)
        while let self, !self.model.lifetime.shouldHide(at: .now) {
          try await Task.sleep(for: .milliseconds(300))
        }
      } catch {
        return  // a newer toast took over
      }
      self?.panel.orderOut(nil)
    }
  }

  private func origin(for size: CGSize, near bounds: CGRect?) -> CGPoint {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { $0.frame.contains(bounds?.origin ?? mouse) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    var origin =
      if let bounds {
        CGPoint(x: bounds.minX, y: bounds.minY - 8 - size.height)
      } else {
        CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height * 0.2)
      }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return origin
  }

  private func makePanel() -> NSPanel {
    let panel = ToastPanel(
      contentRect: CGRect(x: 0, y: 0, width: 280, height: 40),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.animationBehavior = .utilityWindow
    panel.setAccessibilityIdentifier("dict.toast")
    let hosting = FirstMouseHostingView(rootView: ToastView(model: model))
    hosting.sizingOptions = [.intrinsicContentSize]
    panel.contentView = hosting
    return panel
  }
}

@MainActor
@Observable
final class ToastModel {
  var message = ToastMessage.replaced
  @ObservationIgnored var lifetime = ToastLifetime(shownAt: .now)
  var copied = false
}

struct ToastView: View {
  let model: ToastModel

  var body: some View {
    let message = model.message
    let tone = message.isSuccess ? Tone.success : .warning
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    HStack(spacing: Spacing.row) {
      Image(systemName: message.isSuccess ? "checkmark" : "exclamationmark")
        .font(.system(size: Size.toastSymbol, weight: .bold))
        .foregroundStyle(tone.onTint)
        .frame(width: Size.toastDisc, height: Size.toastDisc)
        .background(tone.tint, in: Circle())
        .accessibilityHidden(true)
      Text(message.text)
        .font(Typography.secondary.font)
        .lineSpacing(Typography.secondary.lineSpacing)
        .foregroundStyle(Color(Palette.textPrimary))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: Size.toastText, alignment: .leading)
      if let result = message.copyableResult {
        SecondaryButton(title: model.copied ? "✓" : WritingStrings.copyResult, isCompact: true) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(result, forType: .string)
          model.copied = true
        }
      }
    }
    // The disc and the button sit as far from the ends as from the top and bottom.
    .padding(.leading, (Size.toast - Size.toastDisc) / 2)
    .padding(
      .trailing,
      message.copyableResult == nil
        ? Spacing.blockHorizontal : (Size.toast - Size.compactButton) / 2
    )
    .padding(.vertical, Spacing.tight)
    .frame(minHeight: Size.toast)
    .background(Color(Palette.panelFill), in: shape)
    .overlay(shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5))
    .fixedSize()
    .onHover { model.lifetime.setHovering($0, at: .now) }
  }
}

/// Never key: the app just written into keeps focus.
private final class ToastPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Lets the copy button work on the first click, without making the panel key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension ToastMessage {
  /// The case name, for logs; never the text.
  fileprivate var logName: String {
    switch self {
    case .replaced: "replaced"
    case .notReplaced: "notReplaced"
    case .unconfirmed: "unconfirmed"
    case .failed: "failed"
    }
  }
}
