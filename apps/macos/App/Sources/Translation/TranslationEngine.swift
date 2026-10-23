// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import NaturalLanguage

/// Translates one selection into result panel states (architecture 6.4, 6.5): the model
/// when one is configured, otherwise Apple Translation if the pair's languages happen to be
/// installed, otherwise a notice that a model is needed. Apple Translation also stands in
/// when the model fails. Dict never asks to download translation languages.
@MainActor
final class TranslationEngine {
  /// The configured model; nil without a usable model.
  var model: ModelTranslator?
  private let apple: any Translator
  private let appleAvailability:
    @Sendable (Locale.Language, Locale.Language) async -> AppleTranslationAvailability

  init(
    model: ModelTranslator? = nil,
    apple: any Translator = AppleTranslator.shared,
    appleAvailability:
      @escaping @Sendable (Locale.Language, Locale.Language) async ->
      AppleTranslationAvailability = AppleTranslator.availability
  ) {
    self.model = model
    self.apple = apple
    self.appleAvailability = appleAvailability
  }

  /// Translates `text` and reports every state to show, starting with an empty
  /// `.generating`. Returns when done; cancel the calling task to stop, after which nothing
  /// more is reported.
  func translate(
    _ text: String, direction: Direction, pair: LanguagePair,
    update: (PanelState) -> Void
  ) async {
    let languages = appleLanguages(
      direction: direction, pair: pair, detected: dominantLanguage(of: text))
    // An unrecognized source is checked as the pair's other language: the framework would
    // otherwise be asked anyway and could offer a download.
    let source = languages.source ?? (languages.target == pair.mine ? pair.learning : pair.mine)
    let availability = appleAvailability
    let appleInstalled = { await availability(source, languages.target) == .installed }
    // With a model the request starts at once; the languages matter only for a fallback.
    let installed = model == nil ? await appleInstalled() : false
    guard !Task.isCancelled else { return }
    let chosen = engine(
      for: .translate, modelConfigured: model != nil, appleTranslationInstalled: installed)
    Log.model.info("translation engine: \(String(describing: chosen), privacy: .public)")

    func show(_ phase: PanelPhase, note: PanelNote? = nil) {
      guard !Task.isCancelled else { return }
      update(PanelState(source: text, phase: phase, note: note))
    }
    func translateWithApple(note: PanelNote?) async throws {
      show(.generating(""), note: note)
      var result = ""
      for try await element in apple.translate(text, from: languages.source, to: languages.target) {
        result = element
      }
      show(.result(result), note: note)
    }

    switch chosen {
    case .model:
      guard let model else { return }
      show(.generating(""))
      var shown = ""
      do {
        for try await element in model.translate(text, direction: direction, pair: pair) {
          shown = element
          show(.generating(shown))
        }
        show(.result(shown))
      } catch {
        Log.model.error("model translation failed: \(errorKind(error), privacy: .public)")
        let hasText = !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canFallBack = error is CancellationError ? false : await appleInstalled()
        switch translationRecovery(
          after: error, hasText: hasText, appleTranslationInstalled: canFallBack)
        {
        case .stop: return
        case .keepPartial:
          show(.partial(shown), note: TranslationStrings.partialNote(error))
        case .fallBack:
          let modelError = error
          do {
            try await translateWithApple(note: TranslationStrings.fallbackNote(modelError))
          } catch {
            Log.model.error("apple translation failed: \(errorKind(error), privacy: .public)")
            // The model's error is the one to fix; Apple Translation was only standing in.
            if !(error is CancellationError) {
              show(.failure(TranslationStrings.modelFailure(modelError)))
            }
          }
        case .showError: show(.failure(TranslationStrings.modelFailure(error)))
        }
      }
    case .appleTranslation:
      do {
        try await translateWithApple(note: nil)
      } catch {
        Log.model.error("apple translation failed: \(errorKind(error), privacy: .public)")
        if let phase = TranslationStrings.appleFailure(error) { show(phase) }
      }
    default:
      show(.needsSetup(TranslationStrings.needsModel))
    }
  }
}

/// The languages Apple Translation translates between. The model translates `.undecided` text
/// between the two languages of the pair; Apple Translation needs a target, so text recognized
/// as my language goes into the learning language and anything else into mine.
func appleLanguages(direction: Direction, pair: LanguagePair, detected: Locale.Language?)
  -> (source: Locale.Language?, target: Locale.Language)
{
  let target =
    switch direction {
    case .intoMine: pair.mine
    case .intoLearning: pair.learning
    case .undecided:
      detected.map { sameLanguage($0, pair.mine) } == true ? pair.learning : pair.mine
    }
  return (detected, target)
}

private func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
  a.languageCode == b.languageCode && a.maximalIdentifier == b.maximalIdentifier
}

/// The language the text is mostly written in, by the system recognizer.
func dominantLanguage(of text: String) -> Locale.Language? {
  guard let language = NLLanguageRecognizer.dominantLanguage(for: text), language != .undetermined
  else { return nil }
  return Locale.Language(identifier: language.rawValue)
}

/// The error's type and case for logs, without associated values, which may carry provider
/// messages.
private func errorKind(_ error: any Error) -> String {
  let description = String(describing: error)
  return "\(type(of: error)).\(description.prefix { $0 != "(" })"
}
