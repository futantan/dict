// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

/// Translates what the user wrote into the learning language for the Write key; a
/// `TranslateOutEngine` in the app.
@MainActor
protocol SessionTranslateOut {
  /// Reports every state to show, starting with an empty `.translatedOut`, and returns when
  /// done; cancel the calling task to stop, after which nothing more is reported. The states'
  /// `replaceable` is false: only the session knows the field.
  func translateOut(
    _ text: String, pair: LanguagePair, context: AppContext, update: (PanelState) -> Void
  ) async
}

/// Translates my language out (architecture 6.5, 6.6): the model when one is configured,
/// otherwise Apple Translation if the pair's languages happen to be installed, otherwise a
/// notice that a model is needed. Apple Translation also stands in when the model fails, as
/// for reading. A complete translation is validated, then translated back with the same
/// engine; the back-translation failing changes nothing but its own line.
@MainActor
final class TranslateOutEngine: SessionTranslateOut {
  /// The configured model; nil without a usable model.
  let model: ModelTranslator?
  private let apple: any Translator
  private let appleAvailability:
    @Sendable (Locale.Language, Locale.Language) async -> AppleTranslationAvailability

  init(
    model: ModelTranslator?,
    apple: any Translator = AppleTranslator.shared,
    appleAvailability:
      @escaping @Sendable (Locale.Language, Locale.Language) async ->
      AppleTranslationAvailability = AppleTranslator.availability
  ) {
    self.model = model
    self.apple = apple
    self.appleAvailability = appleAvailability
  }

  func translateOut(
    _ text: String, pair: LanguagePair, context: AppContext, update: (PanelState) -> Void
  ) async {
    let availability = appleAvailability
    let appleInstalled = { await availability(pair.mine, pair.learning) == .installed }
    // With a model the request starts at once; the languages matter only for a fallback.
    let installed = model == nil ? await appleInstalled() : false
    guard !Task.isCancelled else { return }
    let chosen = engine(
      for: .translateOut, modelConfigured: model != nil, appleTranslationInstalled: installed)
    Log.model.info("translate-out engine: \(String(describing: chosen), privacy: .public)")

    func show(_ phase: PanelPhase, note: PanelNote? = nil) {
      guard !Task.isCancelled else { return }
      update(PanelState(source: text, phase: phase, note: note))
    }
    /// Shows the complete translation with its issues, then the back-translation as it
    /// streams in.
    func finish(
      _ result: String, note: PanelNote?,
      back: () -> AsyncThrowingStream<String, Error>
    ) async {
      var translation = TranslateOut(
        text: result, isComplete: true,
        issues: validate(source: text, result: result, action: .translateOut, pair: pair))
      show(.translatedOut(translation), note: note)
      guard !Task.isCancelled else { return }
      do {
        for try await element in back() {
          translation.backTranslation = .text(element)
          show(.translatedOut(translation), note: note)
        }
        if translation.backTranslation == .pending {
          translation.backTranslation = .unavailable
          show(.translatedOut(translation), note: note)
        }
      } catch {
        guard !(error is CancellationError) else { return }
        Log.model.error("back-translation failed: \(errorKind(error), privacy: .public)")
        translation.backTranslation = .unavailable
        show(.translatedOut(translation), note: note)
      }
    }
    func translateWithApple(note: PanelNote?) async throws {
      show(.translatedOut(TranslateOut()), note: note)
      var result = ""
      for try await element in apple.translate(text, from: pair.mine, to: pair.learning) {
        result = element
      }
      let cleaned = cleanUp(result, source: text)
      await finish(cleaned, note: note) {
        let lines = apple.translate(cleaned, from: pair.learning, to: pair.mine)
        return AsyncThrowingStream { continuation in
          let task = Task {
            do {
              for try await element in lines { continuation.yield(oneLine(element)) }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      }
    }

    switch chosen {
    case .model:
      guard let model else { return }
      show(.translatedOut(TranslateOut()))
      var shown = ""
      do {
        for try await element in model.translateOut(text, pair: pair, context: context) {
          shown = element
          show(.translatedOut(TranslateOut(text: shown)))
        }
      } catch {
        Log.model.error("translate-out failed: \(errorKind(error), privacy: .public)")
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
        return
      }
      await finish(shown, note: nil) { model.backTranslate(shown, pair: pair) }
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

/// `text` on one line, as the model's back-translation is: each line break, with the
/// whitespace around it, becomes one space.
private func oneLine(_ text: String) -> String {
  text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\s*\R\s*/, with: " ")
}

/// The error's type and case for logs, without associated values, which may carry provider
/// messages.
private func errorKind(_ error: any Error) -> String {
  let description = String(describing: error)
  return "\(type(of: error)).\(description.prefix { $0 != "(" })"
}
