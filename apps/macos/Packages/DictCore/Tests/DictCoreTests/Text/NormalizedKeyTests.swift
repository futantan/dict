// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct NormalizedKeyTests {
  @Test(arguments: [
    ("hello", "hello"),
    ("Hello", "hello"),
    ("STATE-OF-THE-ART", "state-of-the-art"),
    ("  hello  ", "hello"),
    ("\n\thello world\r\n", "hello world"),
    ("look   up", "look up"),
    ("look\t\nup", "look up"),
    ("look\u{00A0}up", "look up"),
    ("look\u{3000}up", "look up"),
    ("Ｈｅｌｌｏ", "hello"),
    ("ﬁle", "file"),
    ("cafe\u{0301}", "café"),
    ("Don't", "don't"),
    ("你好", "你好"),
    ("  你好  世界 ", "你好 世界"),
    ("ｶﾀｶﾅ", "カタカナ"),
    ("Straße", "straße"),
    ("😀", "😀"),
    ("", ""),
    ("   ", ""),
    ("\n\t\u{3000}", ""),
  ])
  func normalizes(input: String, expected: String) {
    #expect(normalizedKey(input) == expected)
  }

  @Test func isIdempotent() {
    for text in ["  Ｈｅｌｌｏ\u{3000}World ", "ﬁle  name", "Café"] {
      let once = normalizedKey(text)
      #expect(normalizedKey(once) == once)
    }
  }
}
