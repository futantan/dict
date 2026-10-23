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

  @Test func wireEncodingKeepsDeclarationOrder() {
    let value: JSONValue = [
      "b": 1, "a": ["z": nil, "y": true], "c": [0.5, "x/\"é\n"], "empty": [:], "none": [],
    ]
    #expect(
      String(decoding: value.jsonData(), as: UTF8.self)
        == #"{"b":1,"a":{"z":null,"y":true},"c":[0.5,"x/\"é\n"],"empty":{},"none":[]}"#)
  }

  @Test func membersKeepTheirPlaceWhenSetAndLeaveWhenRemoved() {
    var object: JSONObject = ["a": 1, "b": 2, "c": 3]
    object["b"] = 5
    object["d"] = 4
    object["a"] = nil
    #expect(object.keys == ["b", "c", "d"])
    #expect(object["b"] == 5)
    object.merge(["c": "x", "e": false])
    #expect(object.keys == ["b", "c", "d", "e"])
    #expect(object["c"] == "x")
  }

  @Test func equalityIgnoresOrder() {
    #expect(JSONValue.object(["a": 1, "b": 2]) == .object(["b": 2, "a": 1]))
    #expect(JSONValue.object(["a": 1]) != .object(["a": 1, "b": 2]))
  }

  /// A decoder gives no order, so decoded members are sorted: the same text always decodes
  /// to the same order.
  @Test func decodedMembersAreSorted() throws {
    guard case .object(let object) = try decode(#"{"b":1,"c":2,"a":3}"#) else {
      Issue.record("expected an object")
      return
    }
    #expect(object.keys == ["a", "b", "c"])
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
    #expect(try decode(String(decoding: value.jsonData(), as: UTF8.self)) == value)
  }
}
