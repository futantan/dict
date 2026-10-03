// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation
import SwiftUI
import Translation

/// Apple's on-device Translation framework, the zero-configuration engine (architecture 6.5).
///
/// On macOS 15 a `TranslationSession` only comes from SwiftUI's `.translationTask`, which the
/// result panel's view carries through `appleTranslationHost()`. A request sets the
/// configuration that modifier watches and waits until the session arrives. The panel is
/// visible by then, so the system can attach its language download prompt to it. From macOS 26
/// a session for languages that are already installed is constructed directly, with no view.
@MainActor
@Observable
final class AppleTranslator {
  /// The one host the panel view serves; there is one panel.
  static let shared = AppleTranslator()

  /// Watched by `.translationTask`: a new value, or a new version of the same pair, delivers a
  /// fresh session to `AppleTranslator.serve(_:)`.
  private(set) var configuration: TranslationSession.Configuration?
  @ObservationIgnored private var pending: Job?

  private struct Job: Sendable {
    let id: UUID
    let text: String
    let continuation: CheckedContinuation<String, Error>
  }

  enum Route {
    /// A directly constructed session when the languages are installed (macOS 26), else the
    /// panel's `.translationTask`.
    case automatic
    /// Always the panel's `.translationTask`.
    case panel
  }

  /// Whether the framework translates between the two languages and has them downloaded.
  /// Without a known source language the framework recognizes it when translating, so the
  /// pair counts as installed and any problem surfaces as a translation error.
  nonisolated static func availability(from source: Locale.Language?, to target: Locale.Language)
    async -> AppleTranslationAvailability
  {
    guard let source else { return .installed }
    return AppleTranslationAvailability(
      await LanguageAvailability().status(from: source, to: target))
  }

  /// Translates `text`; throws the framework's `TranslationError`, or `CancellationError`.
  func translation(
    of text: String, from source: Locale.Language?, to target: Locale.Language,
    route: Route = .automatic
  ) async throws -> String {
    if #available(macOS 26, *), route == .automatic, let source,
      await LanguageAvailability().status(from: source, to: target) == .installed
    {
      Log.model.info("apple translation: direct session")
      let session = TranslationSession(installedSource: source, target: target)
      return try await session.translate(text).targetText
    }
    Log.model.info("apple translation: panel session")
    return try await translateInPanel(text, from: source, to: target)
  }

  /// Called by `.translationTask` with each new session. Nonisolated, so the session, which
  /// is not `Sendable`, stays in the modifier's task; only the job crosses to the main actor.
  nonisolated static func serve(_ session: TranslationSession) async {
    guard let job = await shared.takePending() else { return }
    Log.model.info("apple translation: panel session arrived")
    do {
      job.continuation.resume(returning: try await session.translate(job.text).targetText)
    } catch {
      job.continuation.resume(throwing: error)
    }
  }

  private func takePending() -> Job? {
    defer { pending = nil }
    return pending
  }

  private func translateInPanel(
    _ text: String, from source: Locale.Language?, to target: Locale.Language
  ) async throws -> String {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        pending?.continuation.resume(throwing: CancellationError())
        pending = Job(id: id, text: text, continuation: continuation)
        if var current = configuration, current.source == source, current.target == target {
          current.invalidate()
          configuration = current
        } else {
          configuration = TranslationSession.Configuration(source: source, target: target)
        }
      }
    } onCancel: {
      Task { @MainActor in self.cancel(id) }
    }
  }

  private func cancel(_ id: UUID) {
    guard let job = pending, job.id == id else { return }
    pending = nil
    job.continuation.resume(throwing: CancellationError())
  }
}

/// What Apple Translation can do for a language pair right now.
enum AppleTranslationAvailability: Sendable, Equatable {
  case installed
  /// Supported, but the languages are not downloaded yet.
  case needsDownload
  case unsupported

  init(_ status: LanguageAvailability.Status) {
    switch status {
    case .installed: self = .installed
    case .supported: self = .needsDownload
    case .unsupported: self = .unsupported
    @unknown default: self = .unsupported
    }
  }
}

extension AppleTranslator: Translator {
  /// Yields the one finished translation.
  nonisolated func translate(
    _ text: String, from source: Locale.Language?, to target: Locale.Language
  )
    -> AsyncThrowingStream<String, Error>
  {
    AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          continuation.yield(try await self.translation(of: text, from: source, to: target))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension View {
  /// Lets `AppleTranslator.shared` obtain sessions through this view. The result panel's view
  /// carries it, so the language download prompt has a visible window to attach to.
  func appleTranslationHost() -> some View {
    translationTask(AppleTranslator.shared.configuration, action: AppleTranslator.serve)
  }
}
