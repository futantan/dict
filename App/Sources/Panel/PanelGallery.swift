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
      ]
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
