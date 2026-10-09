// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Reads the top-level string fields of a JSON object while it streams in, so the card's
/// `definition` can be shown before the whole answer has arrived (architecture 6.6).
///
/// Deltas may be cut anywhere, inside a key, a value or an escape: all state lives here and
/// the text is read one Unicode scalar at a time. A field appears in `values` once its
/// closing quote has arrived, never half-received. Strings inside nested objects and arrays,
/// numbers and literals are skipped; arrays are read by `decodeCard` once the stream ends.
/// After `.discardText`, start over with a fresh scanner.
public struct TopLevelFieldScanner: Sendable {
  /// The top-level string fields received so far, unescaped.
  public private(set) var values: [String: String] = [:]
  /// Every top-level key received so far, in order, whatever its value's type.
  public private(set) var keys: [String] = []

  /// Nesting of objects and arrays; 1 inside the top-level object.
  private var depth = 0
  private var topLevelIsObject = false
  private var inString = false
  private var escaped = false
  /// At depth 1: the next string is a key, not a value.
  private var expectingKey = false
  /// The raw text of the top-level string being read, quotes and escapes included.
  private var token = String.UnicodeScalarView()
  private var key: String?

  public init() {}

  public mutating func feed(_ delta: String) {
    for scalar in delta.unicodeScalars { read(scalar) }
  }

  private var readsTopLevel: Bool { depth == 1 && topLevelIsObject }

  private mutating func read(_ scalar: Unicode.Scalar) {
    if inString {
      if readsTopLevel { token.append(scalar) }
      if escaped {
        escaped = false
      } else if scalar == "\\" {
        escaped = true
      } else if scalar == "\"" {
        inString = false
        if readsTopLevel { finishString() }
      }
      return
    }
    switch scalar {
    case "\"":
      inString = true
      token = readsTopLevel ? "\"".unicodeScalars : String.UnicodeScalarView()
    case "{", "[":
      if depth == 0 { topLevelIsObject = scalar == "{" }
      depth += 1
      if readsTopLevel { expectingKey = true }
    case "}", "]":
      depth = max(0, depth - 1)
    case ":" where readsTopLevel:
      expectingKey = false
    case "," where readsTopLevel:
      expectingKey = true
    default:
      break
    }
  }

  private mutating func finishString() {
    // The token is a complete JSON string, so the standard decoder handles every escape,
    // surrogate pairs included.
    guard let text = try? JSONDecoder().decode(String.self, from: Data(String(token).utf8))
    else { return }
    if expectingKey {
      key = text
      keys.append(text)
    } else if let key {
      values[key] = text
    }
  }
}
