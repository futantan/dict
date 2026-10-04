// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictBuild

struct TextTests {
  @Test(arguments: [
    ("Take  Off", "take off"), ("  Hospital\n", "hospital"), ("ｆｕｌｌ", "full"), ("Ｗｉｋｉ", "wiki"),
  ])
  func normalizedKeyMatchesDictCore(input: String, key: String) {
    #expect(normalizedKey(input) == key)
  }

  @Test(arguments: [
    ("醫院", "医院"), ("頭髮；發展", "头发；发展"), ("測量；評定等級", "测量；评定等级"), ("医院", "医院"),
    ("run 的複數", "run 的复数"),
  ])
  func convertsTraditionalToSimplified(traditional: String, simplified: String) {
    #expect(toSimplified(traditional) == simplified)
  }

  @Test(arguments: [
    ("醫院", "医院"),
    ("衡量；測量；評定等級。", "衡量；测量；评定等级"),
    ("謊話\n例子: This politician told many lies.", "谎话"),
    ("中線\n* 正體: 中心線[電機工程]", "中线"),
    ("較好、更好﹝good的比較級﹞", "较好、更好（good的比较级）"),
    ("<美口> 元", "（美口） 元"),
    ("光;光線;光亮[U]", "光；光线；光亮"),
    ("眼神[S1][U]", "眼神"),
    ("中心線[電機工程]", "中心线（电机工程）"),
    ("［通訊工程］協會，結合", "（通讯工程）协会，结合"),
    (
      ":Template:計算機 Transmission Control Protocol（傳輸控制協議）之縮寫。",
      "（计算机）Transmission Control Protocol（传输控制协议）之缩写"
    ),
    (":Template:不可數 粵語流行音樂", "粤语流行音乐"),
    ("創建（:Template:之過去式）", "创建"),
  ])
  func cleansGlosses(raw: String, clean: String) {
    #expect(cleanGloss(raw) == clean)
  }

  @Test(arguments: [
    "arena\n====翻译====\n翻譯\n* 漢語：巨蛋",  // first line has no Chinese
    "troll (複數 trolls)\n本詞語需要翻譯為漢語。請協助添加，並移除{{rfdef}}模板。",
    "弹性形变 [[ar:elastic deformation]]",
    "guest 的複數",
    "gung ho的另一種拼寫法",
    "kink (“上氣不接下氣”)的另一種寫法",
    "Achilles reflex之同義詞",
    ":Template:之過去式",
    "drain的棄用形式",
    "connexion的舊寫法",
    "run的單數第三人稱現在式",
    ":Template:廢",
    "  ",
  ])
  func dropsUnusableGlosses(raw: String) {
    #expect(cleanGloss(raw) == nil)
  }

  @Test func keepsGlossesThatOnlyMentionAnotherWord() {
    #expect(cleanGloss("TV 的縮寫，電視") == "TV 的缩写，电视")
    #expect(cleanGloss("女同性戀者") == "女同性恋者")
  }

  @Test func usesTheMostSpecificUsableGlossOfAChain() {
    #expect(senseGloss(["動物", "狗"]) == "狗")
    #expect(senseGloss(["動物", "dog"]) == "动物")
    #expect(senseGloss(["dog"]) == nil)
  }

  @Test(arguments: [
    ("noun", "cat", "noun"), ("name", "London", "noun"), ("verb", "run", "verb"),
    ("verb", "take off", "phrasal verb"), ("adj", "big", "adjective"), ("adv", "fast", "adverb"),
    ("prep", "in", "preposition"), ("conj", "and", "conjunction"), ("pron", "she", "pronoun"),
    ("det", "this", "determiner"), ("article", "the", "determiner"),
    ("intj", "oh", "interjection"), ("proverb", "no pain no gain", "idiom"),
    ("prep_phrase", "at all", "phrase"), ("abbrev", "TV", "abbreviation"),
    ("contraction", "don't", "abbreviation"), ("unknown", "absite", ""), ("suffix", "-ness", ""),
  ])
  func mapsPartsOfSpeech(pos: String, word: String, expected: String) {
    #expect(partOfSpeech(pos, word: word) == expected)
  }
}
