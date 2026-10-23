// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing

@testable import DictApp

/// A 1440 x 900 main display with a 25 pt menu bar and a 70 pt Dock.
private let main = PanelScreen(
  frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
  visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))

/// A 1920 x 1080 display to the left of the main one, slightly lower, without a Dock.
private let left = PanelScreen(
  frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
  visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1055))

/// A display above the main one.
private let above = PanelScreen(
  frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
  visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 875))

struct PanelPlacementTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let anchor: PanelAnchor
    let height: CGFloat
    var screens: [PanelScreen] = [main, left, above]
    var preferred: PanelSide = .below
    let expected: PanelPlacement?

    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(
      name: "below the selection, left edges aligned",
      anchor: .selection(CGRect(x: 300, y: 500, width: 200, height: 18)), height: 120,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 372, width: 400, height: 120), side: .below)
    ),
    Case(
      name: "flips above when the bottom has no room",
      anchor: .selection(CGRect(x: 300, y: 150, width: 200, height: 18)), height: 200,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 176, width: 400, height: 200), side: .above)
    ),
    Case(
      name: "exactly enough room below stays below",
      anchor: .selection(CGRect(x: 300, y: 278, width: 200, height: 18)), height: 200,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 70, width: 400, height: 200), side: .below)
    ),
    Case(
      name: "keeps the previous side above while it still fits",
      anchor: .selection(CGRect(x: 300, y: 500, width: 200, height: 18)), height: 120,
      preferred: .above,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 526, width: 400, height: 120), side: .above)
    ),
    Case(
      name: "previous side above no longer fits, goes below",
      anchor: .selection(CGRect(x: 300, y: 700, width: 200, height: 18)), height: 300,
      preferred: .above,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 392, width: 400, height: 300), side: .below)
    ),
    Case(
      name: "clamped against the right edge",
      anchor: .selection(CGRect(x: 1300, y: 500, width: 120, height: 18)), height: 100,
      expected: PanelPlacement(
        frame: CGRect(x: 1032, y: 392, width: 400, height: 100), side: .below)
    ),
    Case(
      name: "clamped against the left edge",
      anchor: .selection(CGRect(x: 2, y: 500, width: 120, height: 18)), height: 100,
      expected: PanelPlacement(frame: CGRect(x: 8, y: 392, width: 400, height: 100), side: .below)
    ),
    Case(
      name: "height capped at 60 percent of the visible height",
      anchor: .selection(CGRect(x: 300, y: 800, width: 200, height: 18)), height: 2000,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 309, width: 400, height: 483), side: .below)
    ),
    Case(
      name: "neither side fits: larger side, shortened to its room",
      anchor: .selection(CGRect(x: 300, y: 400, width: 200, height: 100)), height: 483,
      expected: PanelPlacement(frame: CGRect(x: 300, y: 508, width: 400, height: 367), side: .above)
    ),
    Case(
      name: "selection covers the screen: free placement",
      anchor: .selection(CGRect(x: 100, y: 80, width: 800, height: 780)), height: 200,
      expected: PanelPlacement(frame: CGRect(x: 520, y: 514, width: 400, height: 200), side: .free)
    ),
    Case(
      name: "secondary display with negative coordinates",
      anchor: .selection(CGRect(x: -1000, y: 300, width: 200, height: 18)), height: 150,
      expected: PanelPlacement(
        frame: CGRect(x: -1000, y: 142, width: 400, height: 150), side: .below)
    ),
    Case(
      name: "secondary display, clamped to its right edge, not the main display",
      anchor: .selection(CGRect(x: -150, y: 300, width: 100, height: 18)), height: 150,
      expected: PanelPlacement(
        frame: CGRect(x: -408, y: 142, width: 400, height: 150), side: .below)
    ),
    Case(
      name: "display above the main one",
      anchor: .selection(CGRect(x: 600, y: 1500, width: 100, height: 18)), height: 150,
      expected: PanelPlacement(
        frame: CGRect(x: 600, y: 1342, width: 400, height: 150), side: .below)
    ),
    Case(
      name: "selection straddling two displays goes with its centre",
      anchor: .selection(CGRect(x: -100, y: 500, width: 300, height: 18)), height: 100,
      expected: PanelPlacement(frame: CGRect(x: 8, y: 392, width: 400, height: 100), side: .below)
    ),
    Case(
      name: "selection centre off every display uses the largest overlap",
      anchor: .selection(CGRect(x: 1400, y: 500, width: 100, height: 18)), height: 100,
      screens: [main],
      expected: PanelPlacement(
        frame: CGRect(x: 1032, y: 392, width: 400, height: 100), side: .below)
    ),
    Case(
      name: "mouse: below the pointer",
      anchor: .mouse(CGPoint(x: 700, y: 600)), height: 100,
      expected: PanelPlacement(frame: CGRect(x: 700, y: 476, width: 400, height: 100), side: .below)
    ),
    Case(
      name: "mouse near the bottom: above the pointer",
      anchor: .mouse(CGPoint(x: 700, y: 120)), height: 100,
      expected: PanelPlacement(frame: CGRect(x: 700, y: 128, width: 400, height: 100), side: .above)
    ),
    Case(
      name: "mouse on the secondary display",
      anchor: .mouse(CGPoint(x: -1900, y: -150)), height: 100,
      expected: PanelPlacement(
        frame: CGRect(x: -1900, y: -142, width: 400, height: 100), side: .above)
    ),
    Case(
      name: "no anchor: main display, centred, top at 20 percent",
      anchor: .none, height: 100,
      expected: PanelPlacement(frame: CGRect(x: 520, y: 614, width: 400, height: 100), side: .free)
    ),
    Case(
      name: "no displays",
      anchor: .none, height: 100, screens: [],
      expected: nil
    ),
  ]

  @Test(arguments: cases)
  func placement(_ c: Case) {
    let placement = PanelLayout.place(
      contentHeight: c.height, anchor: c.anchor, screens: c.screens, preferredSide: c.preferred)
    #expect(placement == c.expected)
  }

  @Test func maxHeightIsSixtyPercentOfVisibleHeight() {
    #expect(PanelLayout.maxHeight(on: main) == 483)
    #expect(PanelLayout.maxHeight(on: left) == 633)
  }
}
