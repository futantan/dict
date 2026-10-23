// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct SSEParserTests {
  /// Feeds `chunks` in order, then ends the stream.
  private func parse(_ chunks: [[UInt8]]) -> [SSEEvent] {
    var parser = SSEParser()
    return chunks.flatMap { parser.feed($0) }
  }

  private func parse(_ chunks: String...) -> [SSEEvent] {
    parse(chunks.map { Array($0.utf8) })
  }

  @Test func dispatchesOnBlankLine() {
    #expect(
      parse("data: {\"a\":1}\n\ndata: [DONE]\n\n")
        == [SSEEvent(data: "{\"a\":1}"), SSEEvent(data: "[DONE]")])
  }

  @Test func eventWithoutBlankLineIsNotDispatched() {
    #expect(parse("data: one\n\ndata: two\n") == [SSEEvent(data: "one")])
  }

  @Test func chunkBoundaryInsideALine() {
    #expect(
      parse("da", "ta: hel", "lo\n", "\n", "data: x\r", "\n\r\n")
        == [SSEEvent(data: "hello"), SSEEvent(data: "x")])
  }

  @Test func multiLineDataJoinsWithNewline() {
    #expect(parse("data: first\ndata:second\ndata\n\n") == [SSEEvent(data: "first\nsecond\n")])
  }

  @Test func commentsAndUnknownFieldsAreIgnored() {
    #expect(
      parse(": keep-alive\n\n:another\nid: 7\nretry: 100\ndata: x\n\n") == [SSEEvent(data: "x")])
  }

  @Test func eventFieldIsKeptAndReset() {
    #expect(
      parse("event: error\ndata: bad\n\ndata: ok\n\n")
        == [SSEEvent(event: "error", data: "bad"), SSEEvent(data: "ok")])
  }

  @Test func onlyOneLeadingSpaceIsStripped() {
    #expect(parse("data:  two spaces\n\n") == [SSEEvent(data: " two spaces")])
  }

  @Test(arguments: ["\r\n", "\r", "\n"])
  func everyLineEndingWorks(ending: String) {
    #expect(parse("data: a\(ending)\(ending)data: b\(ending)\(ending)").map(\.data) == ["a", "b"])
  }

  @Test func leadingByteOrderMarkIsSkipped() {
    #expect(parse("\u{FEFF}data: x\n\n") == [SSEEvent(data: "x")])
  }

  @Test func utf8CharacterSplitAcrossChunks() {
    let bytes = Array("data: 你好🙂\n\n".utf8)
    // Split inside "好" (3 bytes) and inside the emoji (4 bytes).
    let chunks = [Array(bytes[0..<10]), Array(bytes[10..<14]), Array(bytes[14...])]
    #expect(parse(chunks) == [SSEEvent(data: "你好🙂")])
  }

  @Test func emptyDataDoesNotDispatch() {
    #expect(parse("event: ping\n\n").isEmpty)
  }
}
