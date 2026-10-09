// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import DictCore
import Observation
import Synchronization

enum SpeechEvent: Sendable, Equatable {
  /// The first audio of the utterance.
  case started
  /// The word about to be spoken, as a UTF-16 range of the text passed to `speak`. The system
  /// includes trailing punctuation and leading spaces; trim them before highlighting.
  case word(Range<Int>)
}

enum SpeechRate: Sendable, CaseIterable {
  case normal, slow

  /// The utterance rate. Rates are stepped, and writing 0.9 gives about 3.5× speed, so both
  /// are expressed against the system default (0.5); slow is 0.30, about 0.77× (architecture 9).
  var value: Float {
    switch self {
    case .normal: AVSpeechUtteranceDefaultSpeechRate
    case .slow: AVSpeechUtteranceDefaultSpeechRate * 0.6
    }
  }
}

enum SpeechError: Error, Equatable {
  /// No installed voice speaks the language.
  case noVoice
}

/// The app's one long-lived speech synthesizer (architecture 9). Reusing it brings the first
/// audio from about 240 ms down to about 20 ms; `prewarm()` pays that cost silently once.
@MainActor @Observable
final class Speaker {
  enum Output {
    /// The default output device.
    case speakers
    /// Renders into buffers and never makes a sound; for tests. Called off the main actor.
    case render(@Sendable (AVAudioPCMBuffer) -> Void)
  }

  /// The accent for English, from the user's settings.
  var accent: Accent = .american
  /// True from `speak` until its stream ends.
  private(set) var isSpeaking = false

  @ObservationIgnored private let output: Output
  @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
  @ObservationIgnored private var delegate: Delegate?
  @ObservationIgnored private var current: Utterance?
  @ObservationIgnored private var prewarmed = false

  init(output: Output = .speakers) {
    self.output = output
  }

  /// The voice `speak` would use for `language`, and what the user could download to sound
  /// better; for the settings page and the hint beside the card's speaker button.
  func voiceChoice(for language: Locale.Language) -> VoiceChoice {
    resolveVoice(language: language, accent: accent, installed: Self.installedVoices())
  }

  /// Renders one word silently so the first `speak` starts fast. Emits no events and leaves
  /// `isSpeaking` alone; later calls do nothing.
  func prewarm(language: Locale.Language = Locale.Language(identifier: "en")) {
    guard !prewarmed, !synthesizer.isSpeaking,
      let voice = systemVoice(for: language)
    else { return }
    prewarmed = true
    let utterance = AVSpeechUtterance(string: "a")
    utterance.voice = voice
    synthesizer.write(utterance) { _ in }
  }

  /// Speaks `text`, first ending the previous stream normally. The stream ends normally when
  /// the text is done or `stop()` is called, and throws `SpeechError.noVoice` when no voice
  /// speaks the language. Cancelling the consuming task or dropping the stream stops the speech.
  func speak(_ text: String, language: Locale.Language, rate: SpeechRate)
    -> AsyncThrowingStream<SpeechEvent, Error>
  {
    stop()
    let (stream, continuation) = AsyncThrowingStream<SpeechEvent, Error>.makeStream()
    guard let voice = systemVoice(for: language) else {
      continuation.finish(throwing: SpeechError.noVoice)
      return stream
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    utterance.rate = rate.value
    let id = ObjectIdentifier(utterance)
    let live = LiveFlag()
    current = Utterance(utterance: utterance, continuation: continuation, live: live)
    isSpeaking = true
    continuation.onTermination = { [weak self] termination in
      guard case .cancelled = termination else { return }
      Task { @MainActor in self?.stop(id) }
    }

    let delegate = Delegate { [weak self] event in self?.handle(event) }
    self.delegate = delegate
    synthesizer.delegate = delegate
    switch output {
    case .speakers:
      synthesizer.speak(utterance)
    case .render(let onBuffer):
      synthesizer.write(utterance) { buffer in
        guard live.isLive, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
          return
        }
        onBuffer(pcm)
      }
    }
    return stream
  }

  /// Stops at once and ends the current stream normally. Detaches the delegate first and does
  /// not wait for the system: in render mode it neither reports the cancel nor stops rendering.
  func stop() {
    guard let utterance = current else { return }
    current = nil
    utterance.live.isLive = false
    synthesizer.delegate = nil
    delegate = nil
    synthesizer.stopSpeaking(at: .immediate)
    utterance.continuation.finish()
    isSpeaking = false
  }

  private func stop(_ id: ObjectIdentifier) {
    if current?.id == id { stop() }
  }

  private func handle(_ event: Delegate.Event) {
    guard let utterance = current, utterance.id == event.utterance else { return }
    switch event.kind {
    case .started:
      utterance.continuation.yield(.started)
    case .range(let range):
      utterance.continuation.yield(.word(range.location..<(range.location + range.length)))
    case .finished:
      current = nil
      utterance.live.isLive = false
      utterance.continuation.finish()
      isSpeaking = false
    }
  }

  private func systemVoice(for language: Locale.Language) -> AVSpeechSynthesisVoice? {
    guard let chosen = voiceChoice(for: language).voice else { return nil }
    // A voice constructed from a listed identifier comes back nil; look it up instead.
    return AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == chosen.identifier }
  }

  static func installedVoices() -> [VoiceInfo] {
    AVSpeechSynthesisVoice.speechVoices().map { voice in
      VoiceInfo(
        identifier: voice.identifier, name: voice.name, language: voice.language,
        quality: VoiceQuality(voice.quality),
        isNovelty: voice.voiceTraits.contains(.isNoveltyVoice))
    }
  }
}

extension VoiceQuality {
  init(_ quality: AVSpeechSynthesisVoiceQuality) {
    switch quality {
    case .premium: self = .premium
    case .enhanced: self = .enhanced
    default: self = .compact
    }
  }
}

private struct Utterance {
  /// Held so its identity cannot be reused while the synthesizer still reports on it.
  let utterance: AVSpeechUtterance
  let continuation: AsyncThrowingStream<SpeechEvent, Error>.Continuation
  let live: LiveFlag

  var id: ObjectIdentifier { ObjectIdentifier(utterance) }
}

/// Whether an utterance's audio is still wanted; read from the render callback's thread.
private final class LiveFlag: Sendable {
  private let state = Mutex(true)

  var isLive: Bool {
    get { state.withLock { $0 } }
    set { state.withLock { $0 = newValue } }
  }
}

/// Forwards the synthesizer's callbacks to the main actor in order, carrying the utterance's
/// identity rather than the utterance, which is not Sendable.
private final class Delegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
  struct Event: Sendable {
    enum Kind: Sendable {
      case started
      case range(NSRange)
      case finished
    }
    let utterance: ObjectIdentifier
    let kind: Kind
  }

  private let send: @MainActor @Sendable (Event) -> Void

  init(send: @escaping @MainActor @Sendable (Event) -> Void) {
    self.send = send
  }

  private func forward(_ utterance: AVSpeechUtterance, _ kind: Event.Kind) {
    let event = Event(utterance: ObjectIdentifier(utterance), kind: kind)
    DispatchQueue.main.async { [send] in MainActor.assumeIsolated { send(event) } }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance)
  {
    forward(utterance, .started)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
  ) {
    forward(utterance, .range(characterRange))
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    forward(utterance, .finished)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    forward(utterance, .finished)
  }
}
