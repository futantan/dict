// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_TOAST_RENDER_DIR"]

/// `TEST_RUNNER_DICT_TOAST_RENDER_DIR=<dir> xcodebuild test …` writes one PNG per message and
/// appearance into `<dir>`, offscreen; add `-testLanguage zh-Hans` for the Chinese UI.
@MainActor
struct ToastRenderTests {
  @Test func everyMessageLaysOut() {
    for (name, model) in Self.samples() {
      let size = NSHostingView(rootView: ToastView(model: model)).fittingSize
      #expect(size.height >= 28 && size.height < 120, "\(name)")
      #expect(size.width > 100 && size.width < 520, "\(name)")
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderMessages() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    for (name, model) in Self.samples() {
      for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let png = try #require(Self.render(model, appearance: appearance))
        try png.write(
          to: directory.appendingPathComponent("toast-\(language)-\(scheme)-\(name).png"))
      }
    }
  }

  private static func samples() -> [(String, ToastModel)] {
    func model(_ message: ToastMessage, copied: Bool = false) -> ToastModel {
      let model = ToastModel()
      model.message = message
      model.copied = copied
      return model
    }
    return [
      ("replaced", model(.replaced)),
      ("not-replaced", model(.notReplaced(result: "A sample correction."))),
      ("not-replaced-copied", model(.notReplaced(result: "A sample correction."), copied: true)),
      ("unconfirmed", model(.unconfirmed(clipboardHoldsResult: false))),
      ("unconfirmed-clipboard", model(.unconfirmed(clipboardHoldsResult: true))),
      ("failed", model(.failed(result: "A sample correction."))),
    ]
  }

  /// Draws the toast on a neutral backdrop with some room around it, at 2x.
  private static func render(_ model: ToastModel, appearance: NSAppearance.Name) -> Data? {
    let content = NSHostingView(rootView: ToastView(model: model))
    content.appearance = NSAppearance(named: appearance)
    content.frame.size = content.fittingSize
    let inset: CGFloat = 24
    let canvas = Backdrop(
      frame: CGRect(
        x: 0, y: 0, width: content.frame.width + inset * 2,
        height: content.frame.height + inset * 2))
    let window = NSWindow(
      contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = canvas
    content.frame.origin = CGPoint(x: inset, y: inset)
    canvas.addSubview(content)
    canvas.layoutSubtreeIfNeeded()

    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * 2),
        pixelsHigh: Int(canvas.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    bitmap.size = canvas.bounds.size
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }

  /// A neutral backdrop, like a document window behind the toast.
  private final class Backdrop: NSView {
    override func draw(_ dirtyRect: CGRect) {
      let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      NSColor(white: dark ? 0.12 : 0.82, alpha: 1).setFill()
      bounds.fill()
    }
  }
}
