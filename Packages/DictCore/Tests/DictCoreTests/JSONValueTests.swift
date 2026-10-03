// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct JSONValueTests {
  private func encode(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  private func decode(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }

  @Test func encodesAsPlainJSON() throws {
    let value = JSONValue.object([
      "max_tokens": .number(800),
      "stream": .bool(true),
      "stop": .null,
      "messages": .array([.object(["role": .string("user")])]),
    ])

    #expect(
      try encode(value)
        == #"{"max_tokens":800,"messages":[{"role":"user"}],"stop":null,"stream":true}"#)
  }

  @Test func integralNumbersEncodeWithoutFraction() throws {
    #expect(try encode(.number(800)) == "800")
    #expect(try encode(.number(0.5)) == "0.5")
  }

  @Test func booleansStayBooleansAndNumbersStayNumbers() throws {
    #expect(
      try decode("[true, 1, 0, false]")
        == .array([.bool(true), .number(1), .number(0), .bool(false)]))
  }

  @Test(arguments: [
    #"{"reasoning_effort":"none"}"#,
    #"{"a":[1,2.5,"x",null,{"b":false}],"c":{}}"#,
    "[]",
    "null",
  ])
  func roundTrips(json: String) throws {
    let value = try decode(json)
    #expect(try decode(try encode(value)) == value)
  }
}
