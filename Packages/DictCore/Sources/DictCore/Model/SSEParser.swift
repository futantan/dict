// SPDX-License-Identifier: GPL-3.0-or-later

/// One server-sent event.
struct SSEEvent: Sendable, Equatable {
  var event: String?
  var data: String

  init(event: String? = nil, data: String) {
    self.event = event
    self.data = data
  }
}

/// Parses a server-sent-event byte stream following the WHATWG rules: a blank line ends
/// an event, lines starting with ":" are comments, several "data:" lines join with "\n".
///
/// Lines are split on raw bytes and decoded only when complete, so a UTF-8 character cut
/// between two network chunks decodes correctly. An event not ended by a blank line before
/// the stream closes is dropped, as the standard requires.
struct SSEParser: Sendable {
  private var line: [UInt8] = []
  private var data = ""
  private var hasData = false
  private var event: String?
  private var afterCarriageReturn = false
  private var atStart = true

  init() {}

  /// Consumes one byte; returns the event it completes, if any.
  mutating func push(_ byte: UInt8) -> SSEEvent? {
    switch byte {
    case 0x0A where afterCarriageReturn:
      afterCarriageReturn = false
      return nil
    case 0x0A, 0x0D:
      afterCarriageReturn = byte == 0x0D
      return endLine()
    default:
      afterCarriageReturn = false
      line.append(byte)
      return nil
    }
  }

  /// Consumes a chunk; returns the events it completes.
  mutating func feed(_ bytes: some Sequence<UInt8>) -> [SSEEvent] {
    bytes.compactMap { push($0) }
  }

  private mutating func endLine() -> SSEEvent? {
    var text = String(decoding: line, as: UTF8.self)
    line.removeAll(keepingCapacity: true)
    if atStart {
      atStart = false
      if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    }
    if text.isEmpty { return dispatch() }
    if text.hasPrefix(":") { return nil }

    let field: Substring
    var value: Substring
    if let colon = text.firstIndex(of: ":") {
      field = text[..<colon]
      value = text[text.index(after: colon)...]
      if value.hasPrefix(" ") { value.removeFirst() }
    } else {
      field = text[...]
      value = ""
    }
    switch field {
    case "data":
      if hasData { data += "\n" }
      data += value
      hasData = true
    case "event":
      event = String(value)
    default:
      break
    }
    return nil
  }

  private mutating func dispatch() -> SSEEvent? {
    defer {
      data = ""
      hasData = false
      event = nil
    }
    guard hasData else { return nil }
    return SSEEvent(event: event, data: data)
  }
}
