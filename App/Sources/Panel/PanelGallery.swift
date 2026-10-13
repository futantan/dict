// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import DictCore
  import SwiftUI

  /// Sample states for previews, offscreen renders and the on-screen demo
  /// (`App/Tests/Panel/PanelGalleryTests.swift`). The sample text follows the app's UI
  /// language, standing in for what the session coordinator and M1.10 will supply.
  enum PanelGallery {
    static func states(chinese: Bool = isChineseUI) -> [(name: String, state: PanelState)] {
      let text = chinese ? Sample.chinese : Sample.english
      return [
        ("input", .input),
        ("reading", PanelState(phase: .reading)),
        ("generating-empty", PanelState(source: text.source, phase: .generating(""))),
        ("generating", PanelState(source: text.source, phase: .generating(text.partial))),
        ("result", PanelState(source: text.source, phase: .result(text.result))),
        ("result-long", PanelState(source: text.longSource, phase: .result(text.longResult))),
        ("failure", PanelState(source: text.source, phase: .failure(text.failure))),
        ("needs-setup", PanelState(phase: .needsSetup(text.setup))),
        (
          "result-note",
          PanelState(source: text.source, phase: .result(text.result), note: PanelNote(text.note))
        ),
        // The real wording, in the UI language of the run.
        (
          "needs-model",
          PanelState(source: text.source, phase: .needsSetup(TranslationStrings.needsModel))
        ),
        (
          "result-note-settings",
          PanelState(
            source: text.source, phase: .result(text.result),
            note: TranslationStrings.fallbackNote(ModelError.unauthorized))
        ),
        (
          "partial-interrupted",
          PanelState(
            source: text.source, phase: .partial(text.partial),
            note: TranslationStrings.incompleteNote(ModelTranslationError.interrupted))
        ),
      ] + writeStates + cardStates
    }

    /// The Write key's states. The text is English in either UI language: it is the
    /// language being learned that gets proofread.
    static var writeStates: [(name: String, state: PanelState)] {
      let changed = AppliedEdits(
        text: "She has lived here since 2019 and works at a bakery.",
        segments: [
          .unchanged("She "),
          .changed(from: "have", to: "has"),
          .unchanged(" lived here "),
          .changed(from: "for", to: "since"),
          .unchanged(" 2019 and "),
          .changed(from: "work", to: "works"),
          .unchanged(" at "),
          .changed(from: "", to: "a "),
          .unchanged("bakery."),
        ])
      // A replacement, a deletion and an insertion declined; the current change accepted.
      var partial = Correction(
        AppliedEdits(
          text: "She has lived here since 2019 and works at a bakery.",
          segments: [
            .unchanged("She "),
            .changed(from: "have", to: "has"),
            .unchanged(" lived "),
            .changed(from: "right ", to: ""),
            .unchanged("here "),
            .changed(from: "for", to: "since"),
            .unchanged(" 2019 and "),
            .changed(from: "work", to: "works"),
            .unchanged(" at "),
            .changed(from: "", to: "a "),
            .unchanged("bakery."),
          ]), replaceable: true)
      for change in [1, 2, 4] { partial.toggle(change) }
      partial.current = 3
      // Return was pressed with every change declined.
      var declined = Correction(changed, replaceable: true)
      for change in 0..<declined.changeCount { declined.toggle(change) }
      declined.current = 0
      declined.declinedReturn = true
      let clean = AppliedEdits(
        text: "She has lived here since 2019.",
        segments: [.unchanged("She has lived here since 2019.")])
      return [
        ("checking", PanelState(phase: .checking(Write.original))),
        ("corrected", PanelState(phase: .corrected(Correction(changed, replaceable: true)))),
        (
          "corrected-read-only",
          PanelState(phase: .corrected(Correction(changed, replaceable: false)))
        ),
        ("proofread-partial", PanelState(phase: .corrected(partial))),
        ("proofread-all-rejected", PanelState(phase: .corrected(declined))),
        (
          "corrected-no-mistakes",
          PanelState(phase: .corrected(Correction(clean, replaceable: true)))
        ),
      ]
    }

    private enum Write {
      static let original = "She have lived here for 2019 and work at bakery."
    }

    /// The word card in each of its states (architecture 6.6). The dictionary is English to
    /// Simplified Chinese, so the card's content is a Chinese speaker's in either UI language;
    /// only the card's own wording follows the UI.
    static var cardStates: [(name: String, state: PanelState)] {
      func card(
        entry: LexiconEntry? = Card.run, _ change: (inout CardState) -> Void = { _ in }
      ) -> PanelState {
        var state = CardState(
          term: "ran", context: Card.context, entry: entry, accent: .american, model: .loading)
        change(&state)
        return PanelState(phase: .card(state))
      }
      var rare = Card.run
      rare.band = .rare
      return [
        ("card-dictionary", card()),
        (
          "card-streaming",
          card {
            $0.show(
              definition: Card.word.definition, contextTranslation: Card.word.contextTranslation)
          }
        ),
        ("card-complete", card { $0.show(Card.word) }),
        ("card-no-dictionary", card(entry: nil) { $0.show(Card.word) }),
        ("card-rare", card(entry: rare) { $0.show(Card.word) }),
        // The longest a header and a sense get: the title and the band must not truncate.
        (
          "card-long",
          {
            var state = CardState(
              term: "antidisestablishmentarianism", context: Card.longContext, entry: Card.long,
              accent: .british, model: .loading)
            state.show(Card.longWord)
            state.encounters = 12
            return PanelState(phase: .card(state))
          }()
        ),
        (
          "card-learning",
          card {
            $0.show(Card.word)
            $0.encounters = 1
            $0.isLearning = true
          }
        ),
        (
          "card-encounters",
          card {
            $0.show(Card.word)
            $0.encounters = 2
          }
        ),
        (
          "card-no-model",
          {
            var state = card { $0.model = .unavailable }
            state.note = CardStrings.needsModelNote
            return state
          }()
        ),
        (
          "card-failed",
          {
            var state = card { $0.model = .unavailable }
            state.note = CardStrings.failureNote(ModelError.network(code: -1009))
            return state
          }()
        ),
        (
          "translation-look-up",
          PanelState(source: "ran", phase: .result("跑；经营"), offersLookUp: true)
        ),
        ("nothing-to-look-up", PanelState(phase: .failure(CardStrings.nothingToLookUp))),
      ]
    }

    private enum Card {
      static let context = "She ran a small bakery for ten years."
      static let longContext =
        "His antidisestablishmentarianism set him against every reformer in the parish, "
        + "and he said so at every meeting."
      static let long = LexiconEntry(
        lemma: "antidisestablishmentarianism", ipaUS: "/ˌæntaɪˌdɪsɪˌstæblɪʃmənˈtɛəriənɪzəm/",
        ipaUK: "/ˌæntiˌdɪsɪˌstæblɪʃmənˈteəriənɪzəm/", band: .rare,
        senses: [
          LexiconSense(
            pos: "noun", gloss: "反对废除国教主义（十九世纪英国反对解除英国国教会国教地位的政治主张）", source: "en")
        ])
      static let longWord = WordCard(
        status: .ok, lemma: "antidisestablishmentarianism", phonetic: "", partOfSpeech: "noun",
        definition: "反对废除国教的立场",
        contextTranslation: "他反对废除国教的立场让他与教区里的每一位改革者为敌，而且他在每次集会上都这么说。",
        otherSenses: [], examples: [], collocations: [], level: "")
      static let run = LexiconEntry(
        lemma: "run", ipaUS: "/ɹʌn/", ipaUK: "/rʌn/", band: .common,
        senses: [
          LexiconSense(pos: "verb", gloss: "跑、奔跑、走", source: "en"),
          LexiconSense(pos: "verb", gloss: "流", source: "en"),
          LexiconSense(pos: "verb", gloss: "经营、管理", source: "en"),
        ])
      static let word = WordCard(
        status: .ok, lemma: "run", phonetic: "/rʌn/", partOfSpeech: "verb",
        definition: "经营；管理", contextTranslation: "她经营一家小面包店十年了。",
        otherSenses: [
          WordCard.Sense(partOfSpeech: "verb", definition: "跑；奔跑"),
          WordCard.Sense(partOfSpeech: "verb", definition: "运行；运转"),
        ],
        examples: [
          WordCard.Example(
            sentence: "He runs the family business now.", translation: "现在由他经营家族生意。")
        ],
        collocations: [
          WordCard.Collocation(phrase: "run a business", meaning: "经营生意"),
          WordCard.Collocation(phrase: "run a meeting", meaning: "主持会议"),
        ],
        level: "B1")
    }

    static var isChineseUI: Bool {
      Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? false
    }

    private struct Sample {
      let source: String
      let partial: String
      let result: String
      let longSource: String
      let longResult: String
      let failure: PanelNotice
      let setup: PanelNotice
      let note: String

      /// A Chinese UI: the user reads English and gets Chinese.
      static let chinese = Sample(
        source: "The quick brown fox jumps over the lazy dog, then naps in the afternoon sun.",
        partial: "敏捷的棕色狐狸跳过了那只",
        result: "敏捷的棕色狐狸跳过那只懒狗，然后在午后的阳光下打了个盹。",
        longSource: String(repeating: longEnglish + "\n\n", count: 4).trimmed,
        longResult: String(repeating: longChinese + "\n\n", count: 6).trimmed,
        failure: PanelNotice(
          title: "无法连接到 OpenAI",
          message: "网络连接似乎已断开。已改用 Apple 翻译。",
          actions: [PanelAction(id: "retry", title: "重试", isDefault: true)]),
        setup: PanelNotice(
          symbol: "hand.raised.fill",
          title: "需要辅助功能权限",
          message: "Dict 需要辅助功能权限才能读取你选中的文字。打开系统设置，在“隐私与安全性 → 辅助功能”里打开 Dict。",
          actions: [
            PanelAction(id: "later", title: "以后再说"),
            PanelAction(id: "open", title: "打开系统设置", isDefault: true),
          ]),
        note: "模型出错（网络错误），已改用 Apple 翻译。")

      /// An English UI: the user reads Chinese and gets English.
      static let english = Sample(
        source: "他把一句很长的话翻来覆去地想了好几遍，最后还是决定不说出口。",
        partial: "He turned a long sentence over in his",
        result:
          "He turned a long sentence over in his mind several times, and in the end decided "
          + "not to say it.",
        longSource: String(repeating: longChinese + "\n\n", count: 4).trimmed,
        longResult: String(repeating: longEnglish + "\n\n", count: 6).trimmed,
        failure: PanelNotice(
          title: "Can’t reach OpenAI",
          message: "The network connection appears to be offline. Switched to Apple Translation.",
          actions: [PanelAction(id: "retry", title: "Try Again", isDefault: true)]),
        setup: PanelNotice(
          symbol: "hand.raised.fill",
          title: "Accessibility permission needed",
          message:
            "Dict needs Accessibility permission to read the text you select. Open System "
            + "Settings and turn on Dict in Privacy & Security → Accessibility.",
          actions: [
            PanelAction(id: "later", title: "Not Now"),
            PanelAction(id: "open", title: "Open System Settings", isDefault: true),
          ]),
        note: "The model failed (network error), so Apple Translation was used.")

      static let longEnglish =
        "Language models read text as tokens, and a sentence that looks short to a person "
        + "may be long to the model. The panel scrolls once the result is taller than 60 "
        + "percent of the screen, and keeps its top edge where it first appeared."
      static let longChinese =
        "语言模型以词元为单位读取文字，一句在人看来很短的话，对模型来说可能很长。"
        + "结果超过屏幕高度的百分之六十时，面板开始滚动，并保持顶边在最初出现的位置。"
    }
  }

  extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  #Preview("Result") {
    PanelView(model: PanelModel(state: PanelGallery.states()[4].state))
  }

  #Preview("Needs setup") {
    PanelView(model: PanelModel(state: PanelGallery.states()[7].state))
  }
#endif
