// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import Foundation

// Prompt evaluation against a `TextModel` (architecture 14.5). It lives in the DictEval
// executable so it never ships with the app; DictCoreTests imports DictEval to unit-test the
// checks and the runner with a stub model.

// MARK: Cases and checks

/// What one case asks the model to do.
enum EvalTask: Sendable, Equatable {
  /// Translate `source` the way the device decided.
  case translation(source: String, direction: Direction)
  /// The dictionary card of `term` in `context`.
  case card(term: String, context: String?)
  /// Translate what the user wrote in their own language out into the learning language for
  /// `context`, then back-translate the cleaned result.
  case translateOut(source: String, context: AppContext)
}

/// One evaluation input: the task and the invariants its output must keep.
struct EvalCase: Sendable {
  var id: String
  var task: EvalTask
  var checks: [EvalCheck]

  init(id: String, source: String, direction: Direction, checks: [EvalCheck]) {
    self.init(id: id, task: .translation(source: source, direction: direction), checks: checks)
  }

  init(id: String, term: String, context: String?, checks: [EvalCheck]) {
    self.init(id: id, task: .card(term: term, context: context), checks: checks)
  }

  init(id: String, translateOut source: String, context: AppContext, checks: [EvalCheck]) {
    self.init(id: id, task: .translateOut(source: source, context: context), checks: checks)
  }

  init(id: String, task: EvalTask, checks: [EvalCheck]) {
    self.id = id
    self.task = task
    self.checks = checks
  }
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
  /// Cards. The answer decodes with `decodeCard`: valid JSON, every field, enums and array
  /// limits as the schema states. When it fails, no other card invariant is checked.
  case strictDecode
  /// Cards: a term has a lemma, a definition and one or two examples; a non-term has every
  /// string empty and every array empty. Always checked.
  case fieldRules
  /// Cards: the definition, and the context translation when there is a context, are in the
  /// user's own language; without a context the context translation is empty. Always checked.
  case cardLanguage
  /// Cards: no example repeats the context sentence. Always checked.
  case examplesNotContext
  case status
  case lemma
  case contextSense
  /// Translating out: `validate` finds no issue in the cleaned result. Always checked.
  case validates
  /// Translating out: the back-translation of the cleaned result completed. Always checked;
  /// when it fails, no other back-translation invariant is checked.
  case backCompleted
  /// Translating out: the back-translation is in my language's script. Always checked.
  case backLanguage
  /// Translating out: a rough check that the back-translation says what the source said.
  /// Always checked: every number of the source is in it and, for sources with at least six
  /// distinct Han characters, the two sets of distinct Han characters overlap with a Dice
  /// coefficient of at least 0.35. `backKeeps` adds key words.
  case backMeaning
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
  /// Cards: the card's status.
  case status(WordCard.Status)
  /// Cards: the lemma is one of these, ignoring case.
  case lemma([String])
  /// Cards: the definition matches the sense the context sentence uses. It contains at least
  /// one of `expected` (fragments of a gloss of that sense in the user's language) and none of
  /// `wrong` (fragments that only a gloss of another sense of the term would contain).
  case contextSense(expected: [String], wrong: [String])
  /// Translating out: the back-translation contains at least one of these; counted under
  /// `backMeaning`.
  case backKeeps([String])
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
  case .status(let status):
    return EvalResult(invariant: .status, failure: "only for cards: \(status)")
  case .lemma:
    return EvalResult(invariant: .lemma, failure: "only for cards")
  case .contextSense:
    return EvalResult(invariant: .contextSense, failure: "only for cards")
  case .backKeeps:
    return EvalResult(invariant: .backMeaning, failure: "only for translating out")
  }
}

/// Checks a complete card answer: strict decoding first, then the invariants every card gets,
/// then `checks`. `mine` is the script of the user's own language, nil to skip that check.
/// Text checks (`notObeyed`, `keepsVerbatim`, …) look at the raw answer.
func evaluateCard(
  _ output: String, term: String, context: String?, mine: ExpectedScript?, checks: [EvalCheck]
) -> [EvalResult] {
  let context = context ?? ""
  // Text the page put in the term or its sentence may legitimately come back translated.
  let leak = EvalResult(
    invariant: .noPromptLeak, failure: promptLeak(output, source: term + "\n" + context))
  let card: WordCard
  do {
    card = try decodeCard(output)
  } catch {
    return [EvalResult(invariant: .strictDecode, failure: "does not decode"), leak]
  }
  return [
    EvalResult(invariant: .strictDecode, failure: nil), leak,
    EvalResult(invariant: .fieldRules, failure: fieldRuleBreak(card)),
    EvalResult(invariant: .cardLanguage, failure: languageMismatch(card, context, mine)),
    EvalResult(invariant: .examplesNotContext, failure: reusedContext(card, context)),
  ]
    + checks.map { item in
      switch item {
      case .status(let status):
        let failure = card.status == status ? nil : "\(card.status.rawValue)"
        return EvalResult(invariant: .status, failure: failure)
      case .lemma(let lemmas):
        let matches = lemmas.contains { $0.caseInsensitiveCompare(card.lemma) == .orderedSame }
        return EvalResult(invariant: .lemma, failure: matches ? nil : quoted(card.lemma))
      case .contextSense(let expected, let wrong):
        let failure =
          firstContained(wrong, in: card.definition)
          ?? (expected.contains { card.definition.contains($0) }
            ? nil
            : "none of \(expected.map(quoted).joined(separator: ", ")) in "
              + quoted(card.definition))
        return EvalResult(invariant: .contextSense, failure: failure)
      default:
        return check(output, source: term, item)
      }
    }
}

private func fieldRuleBreak(_ card: WordCard) -> String? {
  switch card.status {
  case .ok:
    if card.lemma.isEmpty { return "no lemma" }
    if card.definition.isEmpty { return "no definition" }
    if !(1...WordCard.maxExamples).contains(card.examples.count) {
      return "\(card.examples.count) examples"
    }
    return nil
  case .notATerm:
    let strings = [
      card.lemma, card.phonetic, card.partOfSpeech, card.definition, card.contextTranslation,
      card.level,
    ]
    let empty =
      strings.allSatisfy(\.isEmpty) && card.otherSenses.isEmpty && card.examples.isEmpty
      && card.collocations.isEmpty
    return empty ? nil : "not_a_term with content"
  }
}

private func languageMismatch(_ card: WordCard, _ context: String, _ mine: ExpectedScript?)
  -> String?
{
  guard card.status == .ok else { return nil }
  if let mine, let mismatch = scriptMismatch(card.definition, mine) {
    return "definition: \(mismatch)"
  }
  if context.isEmpty {
    return card.contextTranslation.isEmpty ? nil : "context translation without a context"
  }
  if card.contextTranslation.isEmpty { return "no context translation" }
  if let mine, let mismatch = scriptMismatch(card.contextTranslation, mine) {
    return "context translation: \(mismatch)"
  }
  return nil
}

private func reusedContext(_ card: WordCard, _ context: String) -> String? {
  func normalized(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
  }
  let sentence = normalized(context)
  guard !sentence.isEmpty else { return nil }
  let reused = card.examples.first { normalized($0.sentence) == sentence }
  return reused.map { "example \(quoted($0.sentence))" }
}

/// Prompt text that must never reach the output unless the source itself contains it.
private let promptFragments = [
  "source_text", "source block", "text-processing function", "not a chat assistant",
  "Output only the translation", "as the writer's own message",
  "send your translation as their own message", "源块", "源文本块", "只输出译文", "仅输出译文",
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
  /// Cards: from sending the request to the moment the streamed `definition` was complete.
  var definitionAt: Duration?
  /// Cards: whether the top-level `definition` key came before every array key. Reported,
  /// not checked: only the order of the schema sent decides it.
  var definitionFirst: Bool?
  /// Cards: whether the top-level keys came exactly in the schema's order, `status` first.
  var schemaOrder: Bool?
  /// Translating out: the back-translation of the cleaned result; nil when it did not
  /// complete.
  var backTranslation: String?
  var results: [EvalResult]
}

/// Runs cases against a model, one call at a time, so latencies are not skewed by concurrency.
struct EvalRunner: Sendable {
  var model: any TextModel
  var pair: LanguagePair
  var price: EvalPrice
  /// In dollars. No new call starts once the accumulated cost reaches it.
  var costLimit: Double
  /// Cards are asked for with this accent.
  var accent: Accent = .american
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

  private func request(for task: EvalTask) -> ModelRequest {
    switch task {
    case .translation(let source, let direction):
      PromptBuilder.translation(source, direction: direction, pair: pair, nonce: makeNonce())
    case .card(let term, let context):
      PromptBuilder.card(
        term: term, context: context, pair: pair, accent: accent, nonce: makeNonce())
    case .translateOut(let source, let context):
      PromptBuilder.translateOut(source, pair: pair, context: context, nonce: makeNonce())
    }
  }

  private func run(_ evalCase: EvalCase, attempt: Int) async -> EvalRun {
    if case .translateOut(let source, _) = evalCase.task {
      return await runTranslateOut(evalCase, source: source, attempt: attempt)
    }
    let request = request(for: evalCase.task)
    var scanner = TopLevelFieldScanner()
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
          scanner.feed(delta)
          if run.definitionAt == nil, scanner.values["definition"] != nil {
            run.definitionAt = start.duration(to: clock.now)
          }
        case .discardText:
          // What came before was leaked thinking: the answer starts over.
          run.output = ""
          run.firstContent = nil
          run.definitionAt = nil
          scanner = TopLevelFieldScanner()
        case .finished(let reason, let usage):
          run.finish = reason
          run.usage = usage
        }
      }
      run.completion = start.duration(to: clock.now)
      if case .translation(let source, _) = evalCase.task {
        // The same clean-up the app applies before showing the translation.
        run.output = removingAddedClosingTag(run.output, source: source)
      } else {
        run.definitionFirst = definitionFirst(scanner.keys)
        run.schemaOrder = scanner.keys == WordCard.keys
      }
    } catch {
      run.error = String(describing: error)
    }
    if run.error == nil && run.finish == .complete {
      run.results = [EvalResult(invariant: .completed, failure: nil)] + evaluate(run, evalCase)
    } else {
      let reason = run.error ?? run.finish.map { "finished \($0)" } ?? "no finish reason"
      run.results = [EvalResult(invariant: .completed, failure: reason)]
    }
    return run
  }

  private func evaluate(_ run: EvalRun, _ evalCase: EvalCase) -> [EvalResult] {
    switch evalCase.task {
    case .translation(let source, _):
      return DictEval.evaluate(run.output, source: source, checks: evalCase.checks)
    case .card(let term, let context):
      let mine: ExpectedScript? = pair.mine.languageCode == .chinese ? .han : nil
      return evaluateCard(
        run.output, term: term, context: context, mine: mine, checks: evalCase.checks)
    case .translateOut(let source, _):
      return evaluateTranslateOut(
        run.output, back: run.backTranslation, source: source, pair: pair,
        checks: evalCase.checks)
    }
  }

  /// The forward call, cleaned up the way the app does, then the back-translation of that
  /// result when the forward call completed. Latencies are the forward call's; the usage is
  /// both calls'.
  private func runTranslateOut(_ evalCase: EvalCase, source: String, attempt: Int) async
    -> EvalRun
  {
    let forward = await collect(request(for: evalCase.task))
    var run = EvalRun(
      caseID: evalCase.id, attempt: attempt, output: cleanUp(forward.text, source: source),
      finish: forward.finish, error: forward.error, usage: forward.usage,
      firstContent: forward.firstContent, completion: forward.completion, results: [])
    guard forward.error == nil, forward.finish == .complete else {
      let reason = forward.error ?? forward.finish.map { "finished \($0)" } ?? "no finish reason"
      run.results = [EvalResult(invariant: .completed, failure: reason)]
      return run
    }
    let back = await collect(
      PromptBuilder.translation(run.output, into: pair.mine, nonce: makeNonce()))
    if let usage = back.usage {
      run.usage = Usage(
        inputTokens: (run.usage?.inputTokens ?? 0) + usage.inputTokens,
        outputTokens: (run.usage?.outputTokens ?? 0) + usage.outputTokens)
    }
    if back.error == nil, back.finish == .complete {
      run.backTranslation = removingAddedClosingTag(back.text, source: run.output)
    }
    run.results = [EvalResult(invariant: .completed, failure: nil)] + evaluate(run, evalCase)
    return run
  }

  /// One streamed call, as text.
  private func collect(_ request: ModelRequest) async -> StreamedText {
    let clock = ContinuousClock()
    let start = clock.now
    var streamed = StreamedText()
    do {
      for try await event in model.stream(request) {
        switch event {
        case .thinking:
          break
        case .text(let delta):
          if streamed.firstContent == nil && !delta.isEmpty {
            streamed.firstContent = start.duration(to: clock.now)
          }
          streamed.text += delta
        case .discardText:
          streamed.text = ""
          streamed.firstContent = nil
        case .finished(let reason, let usage):
          streamed.finish = reason
          streamed.usage = usage
        }
      }
      streamed.completion = start.duration(to: clock.now)
    } catch {
      streamed.error = String(describing: error)
    }
    return streamed
  }
}

/// What one streamed call produced.
private struct StreamedText {
  var text = ""
  var finish: FinishReason?
  var error: String?
  var usage: Usage?
  var firstContent: Duration?
  var completion: Duration?
}

/// Checks a cleaned translate-out result and its back-translation (nil when that call did not
/// complete): the invariants every output gets, `validate`, then the back-translation's
/// invariants, then `checks`.
func evaluateTranslateOut(
  _ output: String, back: String?, source: String, pair: LanguagePair, checks: [EvalCheck]
) -> [EvalResult] {
  let backKeeps = checks.flatMap { check -> [[String]] in
    if case .backKeeps(let words) = check { [words] } else { [] }
  }
  let forwardChecks = checks.filter { if case .backKeeps = $0 { false } else { true } }
  let issues = validate(source: source, result: output, action: .translateOut, pair: pair)
  var results =
    evaluate(output, source: source, checks: forwardChecks) + [
      EvalResult(
        invariant: .validates,
        failure: issues.isEmpty ? nil : issues.map { "\($0)" }.joined(separator: ", "))
    ]
  guard let back else {
    results.append(EvalResult(invariant: .backCompleted, failure: "did not complete"))
    return results
  }
  let mine: ExpectedScript = pair.mine.languageCode == .chinese ? .han : .latin
  results += [
    EvalResult(invariant: .backCompleted, failure: nil),
    EvalResult(invariant: .backLanguage, failure: scriptMismatch(back, mine)),
    EvalResult(
      invariant: .backMeaning, failure: meaningLoss(back, source: source, keeps: backKeeps)),
  ]
  return results
}

/// Why `back` does not look like it says what `source` said, or nil: a number of the source
/// is missing, too few of the source's distinct Han characters are in it, or none of a group
/// of key words is.
private func meaningLoss(_ back: String, source: String, keeps: [[String]]) -> String? {
  let backDigits = back.filter { !$0.isWhitespace && $0 != "," }
  if let number = source.matches(of: /[0-9]+/).map({ String($0.output) }).first(where: {
    !backDigits.contains($0)
  }) {
    return "missing \(quoted(number))"
  }
  func han(_ text: String) -> Set<Unicode.Scalar> {
    Set(text.unicodeScalars.filter(\.properties.isIdeographic))
  }
  let sourceHan = han(source)
  if sourceHan.count >= 6 {
    let backHan = han(back)
    let dice =
      2 * Double(sourceHan.intersection(backHan).count)
      / Double(sourceHan.count + backHan.count)
    if dice < 0.35 { return "Han overlap \(String(format: "%.2f", dice))" }
  }
  if let group = keeps.first(where: { group in
    !group.contains { back.localizedCaseInsensitiveContains($0) }
  }) {
    return "none of \(group.map(quoted).joined(separator: ", "))"
  }
  return nil
}

/// Whether `definition` is among `keys` and comes before every array of the card.
private func definitionFirst(_ keys: [String]) -> Bool {
  guard let definition = keys.firstIndex(of: "definition") else { return false }
  return !keys[..<definition].contains { ["otherSenses", "examples", "collocations"].contains($0) }
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
    let ordered = runs.compactMap(\.definitionFirst)
    if !ordered.isEmpty {
      lines.append(
        "  definition    p50 \(seconds(\.definitionAt, 0.5)) p90 \(seconds(\.definitionAt, 0.9))"
          + ", before the arrays in \(ordered.count { $0 })/\(ordered.count)"
          + ", keys in schema order in \(runs.count { $0.schemaOrder == true })/\(ordered.count)")
    }
    for run in runs {
      let failed = run.results.compactMap { result in
        result.failure.map { "\(result.invariant.rawValue) (\($0))" }
      }
      guard !failed.isEmpty else { continue }
      lines.append("  \(run.caseID) #\(run.attempt): \(failed.joined(separator: ", "))")
      lines.append("    → \(run.output.replacingOccurrences(of: "\n", with: "⏎"))")
      if let back = run.backTranslation {
        lines.append("    ← \(back.replacingOccurrences(of: "\n", with: "⏎"))")
      }
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
