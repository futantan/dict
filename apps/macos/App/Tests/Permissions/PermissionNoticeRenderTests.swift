// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import DictApp

private let renderDirectory = ProcessInfo.processInfo.environment["DICT_PERMISSIONS_RENDER_DIR"]

/// Renders every permission notice in the real panel view, offscreen, for review.
///
/// `TEST_RUNNER_DICT_PERMISSIONS_RENDER_DIR=<dir> xcodebuild test …` writes one PNG per issue
/// and appearance into `<dir>`; add `-testLanguage zh-Hans` for the Chinese UI.
@MainActor
struct PermissionNoticeRenderTests {
  @Test func noticesFitThePanel() {
    for issue in PermissionIssue.allCases {
      let height = Self.layOut(issue, appearance: .aqua).height
      #expect(height > 60, "\(issue)")
      #expect(height < 300, "\(issue)")
    }
  }

  @Test(.enabled(if: renderDirectory != nil))
  func renderNotices() throws {
    let directory = URL(fileURLWithPath: try #require(renderDirectory))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "zh" : "en"
    for issue in PermissionIssue.allCases {
      for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let png = try #require(Self.render(issue, appearance: appearance))
        let name = "\(language)-\(scheme)-\(Self.fileName(issue)).png"
        try png.write(to: directory.appendingPathComponent(name))
      }
    }
  }

  private static let app = PermissionGuide.AppIdentity(name: "Dict", bundleID: "au.ibra.dict")

  private static func fileName(_ issue: PermissionIssue) -> String {
    switch issue {
    case .missing(.accessibility): "accessibility"
    case .missing(.postEvent): "post-event"
    case .staleAccessibility: "stale"
    }
  }

  private static func layOut(
    _ issue: PermissionIssue, appearance: NSAppearance.Name
  ) -> (view: NSView, height: CGFloat) {
    var height: CGFloat = 0
    let state = PanelState(phase: .needsSetup(PermissionGuide.notice(for: issue, app: app)))
    let view = NSHostingView(
      rootView: PanelView(model: PanelModel(state: state), onContentHeight: { height = $0 }))
    view.sizingOptions = []
    view.appearance = NSAppearance(named: appearance)
    view.frame = CGRect(x: 0, y: 0, width: PanelLayout.width, height: 600)
    view.layoutSubtreeIfNeeded()
    view.frame.size.height = height.rounded(.up)
    view.layoutSubtreeIfNeeded()
    return (view, height)
  }

  /// Draws the content on a plain stand-in for the panel material, which does not render
  /// offscreen, at 2x.
  private static func render(_ issue: PermissionIssue, appearance: NSAppearance.Name) -> Data? {
    let content = layOut(issue, appearance: appearance).view
    let dark = appearance == .darkAqua
    let backdrop = NSView(frame: content.bounds)
    backdrop.wantsLayer = true
    backdrop.layer?.backgroundColor = NSColor(white: dark ? 0.19 : 0.96, alpha: 1).cgColor
    let window = NSWindow(
      contentRect: backdrop.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentView = backdrop
    backdrop.addSubview(content)
    backdrop.layoutSubtreeIfNeeded()

    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(backdrop.bounds.width * 2),
        pixelsHigh: Int(backdrop.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    bitmap.size = backdrop.bounds.size
    backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:])
  }
}
