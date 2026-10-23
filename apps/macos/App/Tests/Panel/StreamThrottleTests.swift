// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictApp

@MainActor
struct StreamThrottleTests {
  private func streaming(_ text: String) -> PanelState {
    PanelState(source: "Hello", phase: .generating(text))
  }

  private func harness(interval: Duration = .milliseconds(30))
    -> (StreamThrottle, () -> [PanelState])
  {
    var delivered: [PanelState] = []
    let throttle = StreamThrottle(interval: interval) { delivered.append($0) }
    return (throttle, { delivered })
  }

  @Test func theFirstChunkShowsAtOnceAndTheRestOncePerFrame() async throws {
    let (throttle, delivered) = harness()
    var text = ""
    for word in ["你", "好", "，", "世", "界"] {
      text += word
      throttle.submit(streaming(text))
    }
    #expect(delivered() == [streaming("你")])

    try await Task.sleep(for: .milliseconds(80))
    #expect(delivered() == [streaming("你"), streaming("你好，世界")])
  }

  @Test func aFinishedResultShowsAtOnceAndDropsHeldText() async throws {
    let (throttle, delivered) = harness()
    throttle.submit(streaming("你"))
    throttle.submit(streaming("你好"))
    throttle.submit(PanelState(source: "Hello", phase: .result("你好。")))
    #expect(
      delivered() == [streaming("你"), PanelState(source: "Hello", phase: .result("你好。"))])

    try await Task.sleep(for: .milliseconds(80))
    #expect(delivered().count == 2)
  }

  /// A stream that fails shows its last text as incomplete at once, held text or not.
  @Test func anIncompleteResultKeepsTheLastText() async throws {
    let (throttle, delivered) = harness()
    let partial = PanelState(
      source: "Hello", phase: .partial("你好，世"), note: PanelNote("incomplete"))
    throttle.submit(streaming("你"))
    throttle.submit(streaming("你好"))
    throttle.submit(streaming("你好，世"))
    throttle.submit(partial)
    #expect(delivered() == [streaming("你"), partial])

    try await Task.sleep(for: .milliseconds(80))
    #expect(delivered().last == partial)
  }

  /// `.discardText` makes the whole text shorter; the latest state still wins.
  @Test func retractedTextIsNotBroughtBack() async throws {
    let (throttle, delivered) = harness()
    throttle.submit(streaming("<think>"))
    throttle.submit(streaming("<think>plan"))
    throttle.submit(streaming("你"))
    try await Task.sleep(for: .milliseconds(80))
    #expect(delivered() == [streaming("<think>"), streaming("你")])
  }

  @Test func everyStateArrivesInOrderAndTheLastOneLast() async throws {
    let (throttle, delivered) = harness(interval: .milliseconds(10))
    var text = ""
    for index in 0..<200 {
      text += "\(index) "
      throttle.submit(streaming(text))
      if index % 20 == 0 { try await Task.sleep(for: .milliseconds(3)) }
    }
    throttle.submit(PanelState(source: "Hello", phase: .result(text)))
    try await Task.sleep(for: .milliseconds(40))

    let shown = delivered()
    #expect(shown.count < 50)
    #expect(shown.last == PanelState(source: "Hello", phase: .result(text)))
    let texts = shown.compactMap(\.phase.copyableText)
    #expect(zip(texts, texts.dropFirst()).allSatisfy { $1.hasPrefix($0) })
  }

  @Test func cancelDropsHeldText() async throws {
    let (throttle, delivered) = harness()
    throttle.submit(streaming("你"))
    throttle.submit(streaming("你好"))
    throttle.cancel()
    try await Task.sleep(for: .milliseconds(80))
    #expect(delivered() == [streaming("你")])

    // After a cancel the next text shows at once again.
    throttle.submit(streaming("再"))
    #expect(delivered().last == streaming("再"))
  }
}
