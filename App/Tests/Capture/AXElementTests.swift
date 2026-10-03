// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import Foundation
import Testing

@testable import DictApp

struct AXElementTests {
  @Test func equalityComparesTheReferencedElementNotTheWrapperInstance() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let first = AXElement(raw: AXUIElementCreateApplication(pid))
    let second = AXElement(raw: AXUIElementCreateApplication(pid))

    #expect(first.raw !== second.raw)
    #expect(first == second)
    #expect(first != AXElement(raw: AXUIElementCreateApplication(pid + 1)))
  }
}
