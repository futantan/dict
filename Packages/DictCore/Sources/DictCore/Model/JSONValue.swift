// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Any JSON value. Encodes and decodes as plain JSON, so it can carry request-body
/// fragments, JSON schemas and preset data.
///
/// Objects keep their members in declaration order, and `jsonData()` writes them in that
/// order. The order matters on the wire: with strict structured output the model writes its
/// answer's keys in the order of the schema's `properties` (architecture 6.6). `Codable`
/// cannot keep it (`JSONEncoder` reorders keys), so request bodies go out through
/// `jsonData()`.
public enum JSONValue: Sendable, Equatable, Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      // Decoders give no member order; sorting makes it the same on every run.
      let members = try container.decode([String: JSONValue].self)
      self = .object(JSONObject(members.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value.dictionary)
    }
  }

  /// Compact JSON with every object's members in declaration order.
  public func jsonData() -> Data {
    var text = ""
    write(to: &text)
    return Data(text.utf8)
  }

  private func write(to text: inout String) {
    switch self {
    case .null: text += "null"
    case .bool(let value): text += value ? "true" : "false"
    case .number(let value): text += Self.literal(value) ?? "null"
    case .string(let value): text += Self.literal(value) ?? "\"\""
    case .array(let values):
      text += "["
      for (index, value) in values.enumerated() {
        if index > 0 { text += "," }
        value.write(to: &text)
      }
      text += "]"
    case .object(let object):
      text += "{"
      for (index, key) in object.keys.enumerated() {
        if index > 0 { text += "," }
        text += (Self.literal(key) ?? "\"\"") + ":"
        object[key]?.write(to: &text)
      }
      text += "}"
    }
  }

  /// A string or number as `JSONEncoder` writes it: escapes, and integers without a fraction.
  /// Nil for a number JSON cannot hold (NaN, infinity).
  private static func literal(_ value: some Encodable) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
  }
}

/// A JSON object's members in declaration order. Setting an existing key keeps its place,
/// a new key goes last. Equality ignores order, like JSON's.
public struct JSONObject: Sendable, Equatable, ExpressibleByDictionaryLiteral {
  public private(set) var keys: [String] = []
  private var values: [String: JSONValue] = [:]

  /// Later duplicates replace earlier ones in place.
  public init(_ members: [(String, JSONValue)]) {
    for (key, value) in members { self[key] = value }
  }

  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self.init(elements)
  }

  public subscript(key: String) -> JSONValue? {
    get { values[key] }
    set {
      if let newValue {
        if values.updateValue(newValue, forKey: key) == nil { keys.append(key) }
      } else if values.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }

  /// Sets every member of `other`, its values winning.
  public mutating func merge(_ other: JSONObject) {
    for key in other.keys { self[key] = other[key] }
  }

  public var dictionary: [String: JSONValue] { values }

  public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool { lhs.values == rhs.values }
}
