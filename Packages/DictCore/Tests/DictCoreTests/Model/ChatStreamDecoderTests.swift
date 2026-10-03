// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

/// Runs SSE text through the parser and decoder, as the model does with network bytes.
func decodeSSE(_ chunks: [String]) throws -> [StreamEvent] {
  var parser = SSEParser()
  var decoder = ChatStreamDecoder()
  var events: [StreamEvent] = []
  for chunk in chunks {
    for event in parser.feed(Array(chunk.utf8)) where !decoder.isDone {
      events += try decoder.decode(event)
    }
  }
  if !decoder.isDone { events += try decoder.finish() }
  return events
}

/// One streamed chunk carrying `json` as its `choices[0]`.
func chunk(_ choice: String) -> String {
  #"data: {"choices":[\#(choice)]}"# + "\n\n"
}

func delta(_ content: String) -> String {
  chunk(#"{"delta":{"content":\#(jsonString(content))}}"#)
}

func jsonString(_ text: String) -> String {
  String(decoding: (try? JSONEncoder().encode(text)) ?? Data(), as: UTF8.self)
}

let usageChunk =
  #"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":3}}"# + "\n\n"
let stopChunk = chunk(#"{"delta":{},"finish_reason":"stop"}"#)
let done = "data: [DONE]\n\n"

struct ChatStreamDecoderTests {
  @Test func normalStreamEndsComplete() throws {
    let events = try decodeSSE([
      chunk(#"{"delta":{"role":"assistant","content":""}}"#), delta("Hel"), delta("lo"),
      stopChunk, usageChunk, done,
    ])
    #expect(
      events == [
        .text("Hel"), .text("lo"),
        .finished(.complete, Usage(inputTokens: 12, outputTokens: 3)),
      ])
  }

  @Test func eventsAfterDoneAreIgnored() throws {
    #expect(try decodeSSE([delta("a"), stopChunk, done, delta("b")]).count == 2)
  }

  @Test func disconnectWithoutFinishReasonIsUnknown() throws {
    #expect(try decodeSSE([delta("partial")]) == [.text("partial"), .finished(.unknown, nil)])
  }

  @Test func disconnectAfterFinishReasonKeepsIt() throws {
    #expect(try decodeSSE([delta("a"), stopChunk]).last == .finished(.complete, nil))
  }

  @Test(arguments: [("length", FinishReason.truncated), ("content_filter", .refused)])
  func finishReasons(raw: String, expected: FinishReason) throws {
    let events = try decodeSSE([
      delta("a"), chunk(#"{"delta":{},"finish_reason":"\#(raw)"}"#), done,
    ])
    #expect(events.last == .finished(expected, nil))
  }

  @Test func refusalDeltaMeansRefused() throws {
    let events = try decodeSSE([chunk(#"{"delta":{"refusal":"I can't"}}"#), stopChunk, done])
    #expect(events == [.finished(.refused, nil)])
  }

  @Test func commentsAndSplitLinesAreHandled() throws {
    let text = ": OPENROUTER PROCESSING\n\n" + delta("你好") + stopChunk + done
    let bytes = Array(text.utf8)
    // Feed 5 bytes at a time so boundaries fall inside lines and inside characters.
    var parser = SSEParser()
    var decoder = ChatStreamDecoder()
    var events: [StreamEvent] = []
    for index in stride(from: 0, to: bytes.count, by: 5) {
      for event in parser.feed(bytes[index..<min(index + 5, bytes.count)]) {
        events += try decoder.decode(event)
      }
    }
    #expect(events == [.text("你好"), .finished(.complete, nil)])
  }

  @Test func onlyThinkingDeltas() throws {
    let events = try decodeSSE([
      chunk(#"{"delta":{"reasoning_content":"hmm"}}"#),
      chunk(#"{"delta":{"reasoning":"more"}}"#), stopChunk, done,
    ])
    #expect(events == [.thinking, .thinking, .finished(.complete, nil)])
  }

  @Test func thinkTagPrefixIsThinking() throws {
    let events = try decodeSSE([
      delta("<thi"), delta("nk>plan"), delta("ning</th"), delta("ink>\n\nAnswer"), stopChunk, done,
    ])
    #expect(
      events == [.thinking, .thinking, .text("Answer"), .finished(.complete, nil)])
  }

  @Test func orphanCloseTagDiscardsEarlierText() throws {
    let events = try decodeSSE([
      delta("I should translate"), delta(" this.</"), delta("think>\n你好"), stopChunk, done,
    ])
    #expect(
      events == [
        .text("I should translate"), .text(" this."), .discardText, .text("你好"),
        .finished(.complete, nil),
      ])
  }

  @Test func errorInsideA200Stream() {
    #expect(throws: ModelError.server(status: 200)) {
      try decodeSSE([delta("a"), #"data: {"error":{"message":"overloaded"}}"# + "\n\n"])
    }
    #expect(throws: ModelError.rateLimited(retryAfter: nil)) {
      try decodeSSE([#"data: {"error":{"code":429,"message":"slow down"}}"# + "\n\n"])
    }
  }

  @Test func sseErrorEventThrows() {
    #expect(throws: ModelError.server(status: 200)) {
      try decodeSSE([delta("a"), "event: error\ndata: {\"message\":\"x\"}\n\n"])
    }
  }

  @Test func malformedChunkThrows() {
    #expect(throws: ModelError.malformedResponse) { try decodeSSE(["data: {nope\n\n"]) }
  }

  @Test func noEventsIsEmptyResponse() {
    #expect(throws: ModelError.emptyResponse) { try decodeSSE([": ping\n\n"]) }
  }

  @Test func completeNonStreamedResponse() throws {
    var decoder = ChatStreamDecoder()
    let json = #"""
      {"choices":[{"message":{"role":"assistant","content":"<think>x</think>Hi"},
      "finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":2}}
      """#
    #expect(
      try decoder.decodeComplete(Data(json.utf8))
        == [.thinking, .text("Hi"), .finished(.complete, Usage(inputTokens: 5, outputTokens: 2))])
  }
}

struct ThinkFilterTests {
  private func run(_ deltas: [String]) -> [StreamEvent] {
    var filter = ThinkFilter()
    return deltas.flatMap { filter.push($0) } + filter.finish()
  }

  @Test func plainTextPassesThroughUnchanged() {
    #expect(run(["  Hello", " world"]) == [.text("  Hello"), .text(" world")])
  }

  @Test func lessThanThatIsNotATagIsKept() {
    #expect(run(["<", "b>bold</b>"]) == [.text("<b>bold</b>")])
    #expect(run(["a </", "thing"]) == [.text("a "), .text("</thing")])
  }

  @Test func heldBackPartialTagIsFlushedAtEnd() {
    #expect(run(["a</thi"]) == [.text("a"), .text("</thi")])
  }

  @Test func unclosedThinkingYieldsNoText() {
    #expect(run(["<think>forever"]) == [.thinking])
  }

  @Test func orphanCloseBeforeAnyTextDoesNotDiscard() {
    #expect(run(["</think>Hi"]) == [.text("Hi")])
  }
}
