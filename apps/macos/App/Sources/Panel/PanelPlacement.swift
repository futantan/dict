// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Where the panel should appear (architecture 11.1). Screen coordinates are Cocoa's, with
/// the origin at the bottom left of the main display.
enum PanelAnchor: Sendable, Equatable {
  /// The selection's bounds.
  case selection(CGRect)
  /// The mouse location, used when the selection has no bounds.
  case mouse(CGPoint)
  /// Neither is available.
  case none
}

/// One display, as seen by the placement calculation.
struct PanelScreen: Sendable, Equatable {
  /// The whole display; decides which display an anchor belongs to.
  let frame: CGRect
  /// The display minus the menu bar and Dock; the panel stays inside it.
  let visibleFrame: CGRect
}

/// Which side of the anchor the panel sits on.
enum PanelSide: Sendable, Equatable {
  /// Below the anchor; the top edge stays put while the content grows.
  case below
  /// Above the anchor; the bottom edge stays put and the panel grows upwards.
  case above
  /// No usable anchor: the top edge stays put.
  case free
}

struct PanelPlacement: Sendable, Equatable {
  let frame: CGRect
  let side: PanelSide
}

enum PanelLayout {
  static let width: CGFloat = 400
  /// Distance between the selection and the panel.
  static let gap: CGFloat = 8
  /// Minimum distance between the panel and the edges of the visible frame.
  static let margin: CGFloat = 8
  /// The panel never grows beyond this fraction of the visible height; content scrolls.
  static let maxHeightFraction: CGFloat = 0.6
  /// Without an anchor, the top edge sits this fraction of the visible height from the top.
  static let freeTopFraction: CGFloat = 0.2
  /// Below this much room on either side, the panel ignores the selection.
  static let minimumRoom: CGFloat = 96
  /// The mouse pointer covers roughly this much below its hot spot.
  static let pointerHeight: CGFloat = 16

  /// The largest height the panel may take on `screen`.
  static func maxHeight(on screen: PanelScreen) -> CGFloat {
    (screen.visibleFrame.height * maxHeightFraction).rounded(.down)
  }

  /// Places a panel whose content wants `contentHeight` points.
  ///
  /// `preferredSide` is the side used by the previous layout of the same session, so a
  /// panel that grows while streaming stays on its side as long as it fits there.
  static func place(
    contentHeight: CGFloat, anchor: PanelAnchor, screens: [PanelScreen],
    preferredSide: PanelSide = .below
  ) -> PanelPlacement? {
    guard let screen = screen(for: anchor, in: screens) else { return nil }
    let visible = screen.visibleFrame
    let height = min(max(contentHeight, 1), maxHeight(on: screen))

    let target: CGRect
    switch anchor {
    case .selection(let rect):
      target = rect
    case .mouse(let point):
      target = CGRect(x: point.x, y: point.y - pointerHeight, width: 0, height: pointerHeight)
    case .none:
      return free(height: height, on: screen)
    }

    let roomBelow = target.minY - gap - visible.minY
    let roomAbove = visible.maxY - (target.maxY + gap)
    let side: PanelSide
    if preferredSide == .above && roomAbove >= height {
      side = .above
    } else if roomBelow >= height {
      side = .below
    } else if roomAbove >= height {
      side = .above
    } else if max(roomBelow, roomAbove) >= minimumRoom {
      side = roomBelow >= roomAbove ? .below : .above
    } else {
      return free(height: height, on: screen)
    }

    let fitted = min(height, side == .below ? roomBelow : roomAbove)
    let y = side == .below ? target.minY - gap - fitted : target.maxY + gap
    let x = clamp(target.minX, low: visible.minX + margin, high: visible.maxX - margin - width)
    return PanelPlacement(
      frame: CGRect(x: x, y: y, width: width, height: fitted).integral, side: side)
  }

  /// The display the anchor is on: the one containing the anchor's centre, else the one it
  /// overlaps most, else the first (main) display.
  static func screen(for anchor: PanelAnchor, in screens: [PanelScreen]) -> PanelScreen? {
    let rect: CGRect
    switch anchor {
    case .selection(let bounds): rect = bounds
    case .mouse(let point): rect = CGRect(origin: point, size: .zero)
    case .none: return screens.first
    }
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    if let hit = screens.first(where: { contains($0.frame, centre) }) { return hit }
    let overlaps = screens.map { screen -> (PanelScreen, CGFloat) in
      let common = screen.frame.intersection(rect)
      return (screen, common.isNull ? 0 : common.width * common.height)
    }
    if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
    return screens.first
  }

  private static func free(height: CGFloat, on screen: PanelScreen) -> PanelPlacement {
    let visible = screen.visibleFrame
    let top = visible.maxY - (visible.height * freeTopFraction).rounded()
    let frame = CGRect(x: visible.midX - width / 2, y: top - height, width: width, height: height)
    return PanelPlacement(frame: frame.integral, side: .free)
  }

  /// Like `CGRect.contains`, but a point on the top or right edge also counts, so a point at
  /// the very top of a display belongs to it.
  private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
    point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY
      && point.y <= frame.maxY
  }

  private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
    max(low, min(value, high))
  }
}
