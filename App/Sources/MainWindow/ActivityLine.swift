// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import DictCore
import Foundation

/// One row of a list of lookups and sentences, worked out from the log: what the Today page
/// shows and the History page can reuse.
struct ActivityLine: Equatable, Identifiable {
  enum Text: Equatable {
    /// A meaning, with the sentence it was met in after a dash.
    case meaning(String, sentence: String?)
    /// A correction or rewrite as the changes between the two texts.
    case diff([DiffSegment])
    /// A translation or translation out: the result, the source after a dash.
    case result(String, source: String)
  }

  let id: String
  /// The word, or what was done: 「纠错」.
  let title: String
  /// A sentence event's title is in the quieter colour.
  let isEvent: Bool
  /// The part of speech, 「读」 or 「写」.
  let tag: String?
  let tagTone: Tone
  let text: Text
  /// 「Safari · 14:20」.
  let detail: String
  /// The term to mark 要学, and whether it is; nil for a sentence.
  let termID: Int64?
  let isLearning: Bool

  init(
    _ activity: Activity, now: Date, timeZone: TimeZone, locale: Locale,
    appName: (String) -> String? = { ActivityLine.appName(bundleID: $0) }
  ) {
    let date = activity.date
    let time = Self.time(date, now: now, timeZone: timeZone, locale: locale)
    switch activity {
    case .lookup(let lookup):
      let card = lookup.term.card.flatMap { try? decodeCard($0.json) }
      id = "lookup-\(lookup.encounter.id)"
      title = lookup.term.lemma
      isEvent = false
      tag = card.flatMap {
        $0.partOfSpeech.isEmpty ? nil : CardStrings.partOfSpeech($0.partOfSpeech)
      }
      tagTone = .accent
      let meaning = lookup.encounter.sense ?? card?.definition ?? ""
      text = .meaning(meaning, sentence: lookup.encounter.sentence)
      detail = Self.detail(app: lookup.encounter.sourceApp.flatMap(appName), time: time)
      termID = lookup.term.id
      isLearning = lookup.term.tier == .learning
    case .sentence(let event):
      id = "sentence-\(event.id)"
      title = Self.title(event.kind)
      isEvent = true
      tag = event.kind == .translated ? WindowStrings.readTag : WindowStrings.writeTag
      tagTone = event.kind == .translated ? .accent : .success
      switch event.kind {
      case .corrected, .improved: text = .diff(textDiff(event.source, event.result))
      case .translated, .translatedOut: text = .result(event.result, source: event.source)
      }
      detail = Self.detail(app: event.sourceApp.flatMap(appName), time: time)
      termID = nil
      isLearning = false
    }
  }

  /// The app's name as Finder shows it, or nil when it is not installed.
  static func appName(bundleID: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }
    return FileManager.default.displayName(atPath: url.path)
      .replacingOccurrences(of: ".app", with: "")
  }

  private static func title(_ kind: SentenceKind) -> String {
    switch kind {
    case .translated:
      String(
        localized: "Translation", table: "MainWindow", comment: "A translated sentence in a list")
    case .corrected:
      String(localized: "Correction", table: "MainWindow", comment: "A corrected text in a list")
    case .improved:
      String(localized: "Rewrite", table: "MainWindow", comment: "A rewritten text in a list")
    case .translatedOut:
      String(
        localized: "Translation out", table: "MainWindow",
        comment: "A text translated into the language being learnt, in a list")
    }
  }

  private static func detail(app: String?, time: String) -> String {
    [app, time].compactMap(\.self).joined(separator: " · ")
  }

  /// The time today, else the day and time.
  static func time(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String {
    var style = Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute()
    if LocalDay(date, in: timeZone) != LocalDay(now, in: timeZone) {
      style = style.month(.abbreviated).day()
    }
    return date.formatted(style)
  }
}
