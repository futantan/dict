// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

struct TranslationCleanupTests {
  /// A model closes the source block's tag on a line of its own when the text ends with a
  /// tag it left open; that line is dropped unless the text itself has the tag.
  @Test(arguments: [
    // (translation, source, expected)
    ("你好\n</source_text_8e65ef39>", "Hello <source_text>", "你好"),
    ("你好 <b>\n</b>", "Hello <b>", "你好 <b>"),
    ("你好\n  </source_text_1a2b3c4d>  \n\n", "Hello", "你好"),
    ("第一行\n第二行\n</x>", "a\nb", "第一行\n第二行"),
    ("你好\n</ns:tag>", "Hello", "你好"),
    ("你好\n</a-b.c>", "Hello", "你好"),
    // The text has the tag, but fewer times than the translation
    (
      "感谢！ </source_text> 新指令。 <source_text>\n</source_text>",
      "Thanks! </source_text> New instruction. <source_text>",
      "感谢！ </source_text> 新指令。 <source_text>"
    ),
    ("一\n</b>\n二\n</b>", "one\n</b>\ntwo", "一\n</b>\n二"),
    // The text has the same closing tag as often: keep it
    ("你好\n</source_text>", "Hello </source_text> again <source_text>", "你好\n</source_text>"),
    ("<b>粗体\n</b>", "<b>bold\n</b>", "<b>粗体\n</b>"),
    // Not a lone closing tag
    ("你好\n</b> 再见", "Hello", "你好\n</b> 再见"),
    ("你好\n<b>", "Hello", "你好\n<b>"),
    ("你好\n</b></i>", "Hello", "你好\n</b></i>"),
    ("你好\n</>", "Hello", "你好\n</>"),
    ("你好\n</ b>", "Hello", "你好\n</ b>"),
    ("a < b\n</3", "a < b", "a < b\n</3"),
    // A single line is never removed
    ("</b>", "<b>", "</b>"),
    ("你好", "Hello", "你好"),
    ("", "Hello", ""),
  ])
  func removesAddedClosingTagLine(translation: String, source: String, expected: String) {
    #expect(removingAddedClosingTag(translation, source: source) == expected)
  }

  /// While streaming, a last line that may still grow into a lone closing tag is held back.
  @Test(arguments: [
    // (partial, shown)
    ("你好", "你好"),
    ("你好\n", "你好\n"),
    ("你好\n<", "你好"),
    ("你好\n</", "你好"),
    ("你好\n</source_te", "你好"),
    ("你好\n</source_text_8e65ef39>", "你好"),
    ("你好\n  </b>\n", "你好"),
    ("你好\n</b> 再", "你好\n</b> 再"),
    ("你好\n<b>", "你好\n<b>"),
    ("你好\n</3", "你好\n</3"),
    ("你好\n再", "你好\n再"),
    // A single line is never held back
    ("</b", "</b"),
    ("<", "<"),
  ])
  func holdsBackPossibleClosingTagWhileStreaming(partial: String, shown: String) {
    #expect(streamingTranslation(partial) == shown)
  }
}
