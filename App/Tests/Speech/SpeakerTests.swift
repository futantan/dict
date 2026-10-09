// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import DictCore
import Foundation
import Synchronization
import Testing

@testable import DictApp

// Every test renders into buffers: none of them makes a sound (architecture 14.1).

private let english = Locale.Language(identifier: "en")
private let sentence = "The quick brown fox jumps over the lazy dog."

/// Counts rendered audio frames from the synthesizer's thread.
private final class FrameCounter: Sendable {
  private let frames = Mutex(0)
  var count: Int { frames.withLock { $0 } }
  func add(_ buffer: AVAudioPCMBuffer) { frames.withLock { $0 += Int(buffer.frameLength) } }
}

@MainActor
private func englishVoiceInstalled() -> Bool {
  let installed = Speaker.installedVoices()
  if resolveVoice(language: english, accent: .american, installed: installed).voice != nil {
    return true
  }
  print("Skipped: no usable English system voice is installed on this Mac.")
  return false
}

@MainActor
private func renderingSpeaker() -> (Speaker, FrameCounter) {
  let counter = FrameCounter()
  return (Speaker(output: .render { counter.add($0) }), counter)
}

/// Waits for `condition` while the main run loop delivers the synthesizer's callbacks.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(10)
  while !condition() {
    try #require(Date() < deadline, "timed out")
    try await Task.sleep(for: .milliseconds(10))
  }
}

@MainActor @Suite(.serialized)
struct SpeakerTests {
  @Test func rendersAnEnglishSentenceIntoAudioFrames() async throws {
    guard englishVoiceInstalled() else { return }
    let choice = resolveVoice(
      language: english, accent: .american, installed: Speaker.installedVoices())
    let voice = try #require(
      AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == choice.voice?.identifier })
    let utterance = AVSpeechUtterance(string: sentence)
    utterance.voice = voice
    let synthesizer = AVSpeechSynthesizer()
    let counter = FrameCounter()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      // The system ends with an empty buffer, sometimes twice: resume once.
      let pending = Mutex<CheckedContinuation<Void, Never>?>(done)
      synthesizer.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength > 0 {
          counter.add(pcm)
        } else {
          pending.withLock { $0.take() }?.resume()
        }
      }
    }
    print("Rendered \(counter.count) frames with \(voice.identifier).")
    #expect(counter.count > 0)
  }

  @Test func theRatesAreStepsOfTheSystemDefault() {
    #expect(SpeechRate.normal.value == AVSpeechUtteranceDefaultSpeechRate)
    #expect(abs(SpeechRate.slow.value - 0.30) < 0.0001)
  }

  @Test func slowTakesLongerThanNormal() async throws {
    guard englishVoiceInstalled() else { return }
    var frames: [SpeechRate: Int] = [:]
    for rate in SpeechRate.allCases {
      let (speaker, counter) = renderingSpeaker()
      for try await _ in speaker.speak(sentence, language: english, rate: rate) {}
      frames[rate] = counter.count
    }
    let normal = try #require(frames[.normal])
    let slow = try #require(frames[.slow])
    #expect(normal > 0)
    #expect(Double(slow) > Double(normal) * 1.15)
  }

  @Test func reportsTheStartAndEachWordInOrder() async throws {
    guard englishVoiceInstalled() else { return }
    let (speaker, _) = renderingSpeaker()
    let stream = speaker.speak(sentence, language: english, rate: .normal)
    #expect(speaker.isSpeaking)
    var events: [SpeechEvent] = []
    for try await event in stream { events.append(event) }

    #expect(events.first == .started)
    let ranges = events.compactMap { event -> Range<Int>? in
      if case .word(let range) = event { range } else { nil }
    }
    #expect(ranges.count >= 9)
    #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.lowerBound < $1.lowerBound })
    #expect(ranges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= sentence.utf16.count })
    #expect(!speaker.isSpeaking)
  }

  @Test func stopEndsTheStreamAndTheAudio() async throws {
    guard englishVoiceInstalled() else { return }
    let (speaker, counter) = renderingSpeaker()
    let long = String(repeating: "This sentence keeps going for a while. ", count: 20)
    var events: [SpeechEvent] = []
    for try await event in speaker.speak(long, language: english, rate: .normal) {
      events.append(event)
      if events.count == 3 { speaker.stop() }
    }
    #expect(!speaker.isSpeaking)
    let framesAtStop = counter.count
    // The system keeps rendering after a stop; none of it may reach the output.
    try await Task.sleep(for: .milliseconds(300))
    #expect(counter.count == framesAtStop)
    #expect(events.count < 20)
  }

  @Test func cancellingTheConsumerStops() async throws {
    guard englishVoiceInstalled() else { return }
    let (speaker, _) = renderingSpeaker()
    let long = String(repeating: "This sentence keeps going for a while. ", count: 20)
    let stream = speaker.speak(long, language: english, rate: .normal)
    let consumer = Task {
      for try await _ in stream {}
    }
    try await eventually { speaker.isSpeaking }
    consumer.cancel()
    try await eventually { !speaker.isSpeaking }
  }

  @Test func aNewUtteranceEndsThePreviousStreamNormally() async throws {
    guard englishVoiceInstalled() else { return }
    let (speaker, _) = renderingSpeaker()
    let long = String(repeating: "This sentence keeps going for a while. ", count: 20)
    let first = speaker.speak(long, language: english, rate: .normal)
    let second = speaker.speak("Hello.", language: english, rate: .slow)
    for try await _ in first {}
    var secondEvents: [SpeechEvent] = []
    for try await event in second { secondEvents.append(event) }
    #expect(secondEvents.first == .started)
    #expect(!speaker.isSpeaking)
  }

  @Test func throwsWhenNoVoiceSpeaksTheLanguage() async {
    let (speaker, counter) = renderingSpeaker()
    let stream = speaker.speak("Hello.", language: Locale.Language(identifier: "xx"), rate: .normal)
    await #expect(throws: SpeechError.noVoice) {
      for try await _ in stream {}
    }
    #expect(!speaker.isSpeaking)
    #expect(counter.count == 0)
  }

  @Test func prewarmIsSilentAndInvisible() async throws {
    guard englishVoiceInstalled() else { return }
    let (speaker, counter) = renderingSpeaker()
    speaker.prewarm()
    #expect(!speaker.isSpeaking)
    try await Task.sleep(for: .milliseconds(300))
    #expect(counter.count == 0)
    var events: [SpeechEvent] = []
    for try await event in speaker.speak("Hello.", language: english, rate: .normal) {
      events.append(event)
    }
    #expect(events.first == .started)
    #expect(counter.count > 0)
  }

  @Test func choosesAnInstalledVoice() {
    guard englishVoiceInstalled() else { return }
    let speaker = Speaker(output: .render { _ in })
    for accent in Accent.allCases {
      speaker.accent = accent
      let choice = speaker.voiceChoice(for: english)
      print(
        "\(accent): \(choice.voice?.identifier ?? "none"), \(choice.voice.map { "\($0.quality)" } ?? "-"), hint \(choice.hint.map { "\($0)" } ?? "none")"
      )
      #expect(choice.voice != nil)
    }
  }
}

struct SpeechStringsTests {
  private func chinese(_ key: String) throws -> String {
    let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    return bundle.localizedString(forKey: key, value: "<missing>", table: "Speech")
  }

  @Test func theButtonsHaveChineseNames() throws {
    #expect(try chinese("Pronounce") == "发音")
    #expect(try chinese("Pronounce Slowly") == "慢速发音")
    #expect(try chinese("Manage Voices…") == "管理语音…")
  }

  @Test func everyHintHasItsOwnText() {
    let hints: [VoiceHint] = [.noVoice, .accentMissing, .higherQuality]
    let texts = hints.compactMap(SpeechStrings.hint)
    #expect(texts.count == hints.count)
    #expect(Set(texts).count == hints.count)
    #expect(SpeechStrings.hint(nil) == nil)
  }
}
