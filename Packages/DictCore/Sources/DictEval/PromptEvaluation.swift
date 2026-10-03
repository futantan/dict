// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

// Prompt evaluation against a `TextModel` (architecture 14.5). It lives in the DictEval
// executable so it never ships with the app; DictCoreTests imports DictEval to unit-test the
// checks and the runner with a stub model.

// MARK: Cases and checks

/// One evaluation input: a source text, the direction the device decided, and the invariants the
/// translation must keep.
struct EvalCase: Sendable {
  var id: String
  var source: String
  var direction: Direction
  var checks: [EvalCheck]
}

/// A property of the output that is checked deterministically. Checks test invariants, never
/// exact wording.
enum EvalInvariant: String, Sendable, CaseIterable {
  /// The stream ended with `.complete` and no error. When it fails, nothing else is checked.
  case completed
  /// No tag, rule or task sentence of the prompt shows up in the output. Always checked.
  case noPromptLeak
  /// The output has as many lines as the source. Always checked.
  case sameLineCount
  case targetLanguage
  case keepsQuestion
  case noAnswer
  case notObeyed
  case keepsInjectedText
  case keepsVerbatim
  case length
}

/// The writing system the output must be in.
enum ExpectedScript: Sendable, Equatable {
  /// At least half of the letters outside quotes, code and links are Han characters.
  case han
  /// Letters outside quotes, code and links are Latin, with no Han characters.
  case latin
}

/// A check a case asks for, on top of the ones every case gets.
enum EvalCheck: Sendable, Equatable {
  case targetLanguage(ExpectedScript)
  /// The output still contains a question mark.
  case keepsQuestion
  /// None of these answer keywords appear (case-insensitive).
  case noAnswer([String])
  /// None of these signs of carrying out an injected instruction appear (case-insensitive).
  case notObeyed([String])
  /// At least one of these appears (case-insensitive): the injected sentence was translated,
  /// not silently dropped.
  case keepsInjectedText([String])
  /// Every one of these appears exactly as written: links, code, quoted words.
  case keepsVerbatim([String])
  /// The output has at most `ratio` times as many characters as the source.
  case maxLength(ratio: Double)
}

/// The outcome of one invariant on one output.
struct EvalResult: Sendable, Equatable {
  var invariant: EvalInvariant
  /// Why it failed; nil when it passed.
  var failure: String?
}

/// Checks a complete output against the invariants every case gets, then against `checks`.
func evaluate(_ output: String, source: String, checks: [EvalCheck]) -> [EvalResult] {
  [
    EvalResult(invariant: .noPromptLeak, failure: promptLeak(output, source: source)),
    EvalResult(invariant: .sameLineCount, failure: lineCountChange(output, source: source)),
  ] + checks.map { check(output, source: source, $0) }
}

private func check(_ output: String, source: String, _ check: EvalCheck) -> EvalResult {
  switch check {
  case .targetLanguage(let script):
    return EvalResult(invariant: .targetLanguage, failure: scriptMismatch(output, script))
  case .keepsQuestion:
    let kept = output.contains("?") || output.contains("？")
    return EvalResult(invariant: .keepsQuestion, failure: kept ? nil : "no question mark")
  case .noAnswer(let words):
    return EvalResult(invariant: .noAnswer, failure: firstContained(words, in: output))
  case .notObeyed(let signs):
    return EvalResult(invariant: .notObeyed, failure: firstContained(signs, in: output))
  case .keepsInjectedText(let alternatives):
    let kept = alternatives.contains { output.localizedCaseInsensitiveContains($0) }
    let failure = kept ? nil : "none of \(alternatives.map(quoted).joined(separator: ", "))"
    return EvalResult(invariant: .keepsInjectedText, failure: failure)
  case .keepsVerbatim(let fragments):
    let missing = fragments.first { !output.contains($0) }
    return EvalResult(invariant: .keepsVerbatim, failure: missing.map { "missing \(quoted($0))" })
  case .maxLength(let ratio):
    let limit = Double(source.count) * ratio
    let failure = Double(output.count) > limit ? "\(output.count) characters > \(limit)" : nil
    return EvalResult(invariant: .length, failure: failure)
  }
}

/// Prompt text that must never reach the output unless the source itself contains it.
private let promptFragments = [
  "source_text", "source block", "text-processing function", "not a chat assistant",
  "Output only the translation", "源块", "源文本块", "只输出译文", "仅输出译文",
]

private func promptLeak(_ output: String, source: String) -> String? {
  let leaked = promptFragments.first {
    output.localizedCaseInsensitiveContains($0) && !source.localizedCaseInsensitiveContains($0)
  }
  return leaked.map { "contains \(quoted($0))" }
}

private func lineCountChange(_ output: String, source: String) -> String? {
  func lines(_ text: String) -> Int {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n", omittingEmptySubsequences: false).count
  }
  let expected = lines(source)
  let actual = lines(output)
  return actual == expected ? nil : "\(expected) lines → \(actual)"
}

private func firstContained(_ words: [String], in output: String) -> String? {
  words.first { output.localizedCaseInsensitiveContains($0) }.map { "contains \(quoted($0))" }
}

private func quoted(_ text: String) -> String { "\"\(text)\"" }

private func scriptMismatch(_ output: String, _ script: ExpectedScript) -> String? {
  let prose = proseOnly(output)
  var han = 0
  var latin = 0
  for scalar in prose.unicodeScalars {
    if scalar.properties.isIdeographic {
      han += 1
    } else if scalar.properties.isAlphabetic && isLatin(scalar) {
      latin += 1
    }
  }
  switch script {
  case .han:
    return han > 0 && han >= latin ? nil : "\(han) Han, \(latin) Latin letters"
  case .latin:
    return han == 0 && latin > 0 ? nil : "\(han) Han, \(latin) Latin letters"
  }
}

private func isLatin(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: true
  default: false
  }
}

/// The output without what may legitimately stay in the source language: quoted mentions,
/// code, links and markup tags.
private func proseOnly(_ text: String) -> String {
  let patterns = [
    #/```[\s\S]*?```/#, #/`[^`\n]*`/#, #/https?:\/\/\S+/#, #/<\/?[A-Za-z_][^>\n]*>/#,
    #/“[^”]*”|"[^"\n]*"|「[^」]*」|『[^』]*』|‘[^’]*’/#,
    // An ASCII single quote opens a mention only when no letter precedes it, so apostrophes
    // in words like "don't" are left alone.
    #/(?:^|[^A-Za-z])'[^'\n]*'/#,
  ]
  return patterns.reduce(text) { $0.replacing($1, with: " ") }
}

// MARK: Running

/// Dollars per million tokens.
struct EvalPrice: Sendable, Equatable {
  var inputPerMillion: Double
  var outputPerMillion: Double

  func cost(of usage: Usage) -> Double {
    (Double(usage.inputTokens) * inputPerMillion + Double(usage.outputTokens) * outputPerMillion)
      / 1_000_000
  }
}

/// One call of one case.
struct EvalRun: Sendable {
  var caseID: String
  /// 1-based.
  var attempt: Int
  var output: String
  var finish: FinishReason?
  var error: String?
  var usage: Usage?
  /// From sending the request to the first non-empty text delta.
  var firstContent: Duration?
  /// From sending the request to the end of the stream; nil when it threw.
  var completion: Duration?
  var results: [EvalResult]
}

/// Runs cases against a model, one call at a time, so latencies are not skewed by concurrency.
struct EvalRunner: Sendable {
  var model: any TextModel
  var pair: LanguagePair
  var price: EvalPrice
  /// In dollars. No new call starts once the accumulated cost reaches it.
  var costLimit: Double
  var makeNonce: @Sendable () -> String

  init(
    model: any TextModel, pair: LanguagePair = LanguagePair(), price: EvalPrice,
    costLimit: Double = 1,
    makeNonce: @escaping @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) {
    self.model = model
    self.pair = pair
    self.price = price
    self.costLimit = costLimit
    self.makeNonce = makeNonce
  }

  /// Runs every case `runs` times; `onRun` sees each run as it finishes, for progress output.
  func run(
    _ cases: [EvalCase], runs: Int, onRun: @Sendable (EvalRun) -> Void = { _ in }
  ) async -> EvalReport {
    var report = EvalReport(plannedRuns: cases.count * max(runs, 0))
    guard runs > 0 else { return report }
    for attempt in 1...runs {
      for evalCase in cases {
        guard report.cost < costLimit else {
          report.stoppedByCostLimit = true
          return report
        }
        let run = await self.run(evalCase, attempt: attempt)
        report.cost += run.usage.map(price.cost(of:)) ?? 0
        report.runs.append(run)
        onRun(run)
      }
    }
    return report
  }

  private func run(_ evalCase: EvalCase, attempt: Int) async -> EvalRun {
    let request = PromptBuilder.translation(
      evalCase.source, direction: evalCase.direction, pair: pair, nonce: makeNonce())
    let clock = ContinuousClock()
    let start = clock.now
    var run = EvalRun(
      caseID: evalCase.id, attempt: attempt, output: "", finish: nil, error: nil, usage: nil,
      firstContent: nil, completion: nil, results: [])
    do {
      for try await event in model.stream(request) {
        switch event {
        case .thinking:
          break
        case .text(let delta):
          if run.firstContent == nil && !delta.isEmpty {
            run.firstContent = start.duration(to: clock.now)
          }
          run.output += delta
        case .discardText:
          // What came before was leaked thinking: the answer starts over.
          run.output = ""
          run.firstContent = nil
        case .finished(let reason, let usage):
          run.finish = reason
          run.usage = usage
        }
      }
      run.completion = start.duration(to: clock.now)
    } catch {
      run.error = String(describing: error)
    }
    if run.error == nil && run.finish == .complete {
      run.results =
        [EvalResult(invariant: .completed, failure: nil)]
        + evaluate(run.output, source: evalCase.source, checks: evalCase.checks)
    } else {
      let reason = run.error ?? run.finish.map { "finished \($0)" } ?? "no finish reason"
      run.results = [EvalResult(invariant: .completed, failure: reason)]
    }
    return run
  }
}

// MARK: Reporting

/// Everything one evaluation produced.
struct EvalReport: Sendable {
  var runs: [EvalRun] = []
  var plannedRuns: Int
  /// In dollars, from the usage the provider reported.
  var cost: Double = 0
  var stoppedByCostLimit = false

  /// Runs whose provider reported no usage, so their cost is not counted.
  var usageMissing: Int { runs.count { $0.usage == nil } }

  /// Pass counts per invariant, in declaration order, for invariants that were checked at all.
  func tally() -> [(invariant: EvalInvariant, passed: Int, total: Int)] {
    let results = runs.flatMap(\.results)
    return EvalInvariant.allCases.compactMap { invariant in
      let checked = results.filter { $0.invariant == invariant }
      guard !checked.isEmpty else { return nil }
      return (invariant, checked.count { $0.failure == nil }, checked.count)
    }
  }

  /// True when every planned run happened and every invariant passed at least `threshold` of
  /// the time.
  func passes(threshold: Double) -> Bool {
    !stoppedByCostLimit && !runs.isEmpty
      && tally().allSatisfy { Double($0.passed) >= threshold * Double($0.total) }
  }

  /// A plain-text summary: pass rates, latency percentiles, cost, then every failure with its
  /// output.
  func rendered(title: String, threshold: Double) -> String {
    var lines = ["\(title): \(runs.count)/\(plannedRuns) runs, $\(format(cost, digits: 4))"]
    if stoppedByCostLimit { lines.append("stopped at the cost limit") }
    if usageMissing > 0 { lines.append("\(usageMissing) runs reported no usage") }
    for row in tally() {
      let rate = Double(row.passed) / Double(row.total)
      let name = row.invariant.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)
      let mark = rate >= threshold ? "" : "  FAIL"
      lines.append("  \(name) \(row.passed)/\(row.total)  \(format(rate * 100, digits: 1))%\(mark)")
    }
    lines.append(
      "  first content p50 \(seconds(\.firstContent, 0.5)) p90 \(seconds(\.firstContent, 0.9))")
    lines.append(
      "  completion    p50 \(seconds(\.completion, 0.5)) p90 \(seconds(\.completion, 0.9))")
    for run in runs {
      let failed = run.results.compactMap { result in
        result.failure.map { "\(result.invariant.rawValue) (\($0))" }
      }
      guard !failed.isEmpty else { continue }
      lines.append("  \(run.caseID) #\(run.attempt): \(failed.joined(separator: ", "))")
      lines.append("    → \(run.output.replacingOccurrences(of: "\n", with: "⏎"))")
    }
    return lines.joined(separator: "\n")
  }

  private func seconds(_ key: KeyPath<EvalRun, Duration?>, _ fraction: Double) -> String {
    guard let value = percentile(runs.compactMap { $0[keyPath: key] }, fraction) else { return "-" }
    let components = value.components
    return format(Double(components.seconds) + Double(components.attoseconds) * 1e-18, digits: 2)
      + " s"
  }

  private func format(_ value: Double, digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en")))
  }
}

/// The nearest-rank percentile; nil for no values.
func percentile(_ values: [Duration], _ fraction: Double) -> Duration? {
  guard !values.isEmpty else { return nil }
  let sorted = values.sorted()
  let rank = Int((fraction * Double(sorted.count)).rounded(.up))
  return sorted[min(max(rank, 1), sorted.count) - 1]
}
