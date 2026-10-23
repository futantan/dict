// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One mistake the model found: a span of the source and its replacement (architecture 6.6).
public struct Edit: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable {
    case spelling, grammar, wordForm = "word_form", punctuation
  }

  public var kind: Kind
  public var wrong: String
  public var right: String

  public init(kind: Kind, wrong: String, right: String) {
    self.kind = kind
    self.wrong = wrong
    self.right = right
  }
}

/// A run of the diff between the source and the corrected text.
public enum DiffSegment: Sendable, Equatable {
  case unchanged(String)
  case changed(from: String, to: String)
}

/// The source with the edits applied, and the diff that renders them (architecture 6.7).
public struct AppliedEdits: Sendable, Equatable {
  public var text: String
  /// The whole source in order: concatenating the `unchanged` runs and the `from` sides
  /// gives the source back; the `to` sides instead give `text`.
  public var segments: [DiffSegment]

  public init(text: String, segments: [DiffSegment]) {
    self.text = text
    self.segments = segments
  }

  public var changeCount: Int {
    segments.count { if case .changed = $0 { true } else { false } }
  }
}

public enum EditError: Error, Sendable, Equatable {
  case notFound(index: Int)
  case ambiguous(index: Int)
  case overlapping(Int, Int)
}

/// Applies `edits` to `source`. Every `wrong` must occur exactly once (overlapping
/// occurrences count) and no two spans may overlap; all spans are located before any is
/// replaced, so one edit never shifts or breaks another. Edits that change nothing are
/// dropped, and so is an edit that a larger one already makes (`absorbed`).
///
/// Models sometimes quote a later span from the text as already corrected by an earlier
/// edit, or put one edit's span inside another's (both measured with gpt-6-luna). When a
/// span is not in the source, the edits are applied in order instead, each span occurring
/// exactly once in the text so far; when spans overlap, the same is tried longest span
/// first, and the overlap is reported if that fails too.
///
/// The diff always compares the two texts, so a span longer than its mistake shows only
/// the words that changed.
public func applyEdits(_ edits: [Edit], to source: String) -> Result<AppliedEdits, EditError> {
  let numbered = kept(edits)
  var result = applyIndependently(numbered, to: source)
  switch result {
  case .failure(.notFound):
    result = applyInOrder(numbered, to: source)
  case .failure(.overlapping):
    let longestFirst = numbered.sorted { $0.element.wrong.count > $1.element.wrong.count }
    if case .success(let text) = applyInOrder(longestFirst, to: source) { result = .success(text) }
  default:
    break
  }
  return result.map { AppliedEdits(text: $0, segments: textDiff(source, $0)) }
}

/// The edits worth applying, with their index in the model's list: not the ones that
/// change nothing, and not one that another edit already makes. Edit `b` is made by `a`
/// when `a.wrong` contains `b.wrong` and `a.right` contains `b.right`; of two identical
/// edits the first is kept.
private func kept(_ edits: [Edit]) -> [(offset: Int, element: Edit)] {
  let changing = edits.enumerated().filter { $0.element.wrong != $0.element.right }
  return changing.filter { b in
    !changing.contains { a in
      a.offset != b.offset && a.element.wrong.contains(b.element.wrong)
        && a.element.right.contains(b.element.right)
        && (a.element != b.element || a.offset < b.offset)
    }
  }
}

/// Replaces the edits one after another, each span occurring exactly once in the text so
/// far; errors carry the edit's index in the model's list.
private func applyInOrder(
  _ edits: [(offset: Int, element: Edit)], to source: String
) -> Result<String, EditError> {
  var text = source
  for (index, edit) in edits {
    let found = occurrences(of: edit.wrong, in: text)
    guard let first = found.first else { return .failure(.notFound(index: index)) }
    guard found.count == 1 else { return .failure(.ambiguous(index: index)) }
    text.replaceSubrange(first, with: fitted(edit, at: first, in: text))
  }
  return .success(text)
}

private func applyIndependently(
  _ edits: [(offset: Int, element: Edit)], to source: String
) -> Result<String, EditError> {
  var spans: [(range: Range<String.Index>, index: Int, right: String)] = []
  for (index, edit) in edits {
    let found = occurrences(of: edit.wrong, in: source)
    guard let first = found.first else { return .failure(.notFound(index: index)) }
    guard found.count == 1 else { return .failure(.ambiguous(index: index)) }
    spans.append((first, index, fitted(edit, at: first, in: source)))
  }
  spans.sort { $0.range.lowerBound < $1.range.lowerBound }
  for (earlier, later) in zip(spans, spans.dropFirst())
  where earlier.range.upperBound > later.range.lowerBound {
    return .failure(.overlapping(min(earlier.index, later.index), max(earlier.index, later.index)))
  }
  var text = source
  for span in spans.reversed() { text.replaceSubrange(span.range, with: span.right) }
  return .success(text)
}

/// `edit.right` without the whitespace it adds next to whitespace the text already has:
/// models sometimes end "right" with a space although the text goes on with one (measured
/// with gpt-6-luna), which would leave two. Whitespace that `wrong` also has is kept.
private func fitted(_ edit: Edit, at range: Range<String.Index>, in text: String) -> String {
  var right = Substring(edit.right)
  if right.last?.isWhitespace == true, edit.wrong.last?.isWhitespace == false,
    range.upperBound < text.endIndex, text[range.upperBound].isWhitespace
  {
    while right.last?.isWhitespace == true { right.removeLast() }
  }
  if right.first?.isWhitespace == true, edit.wrong.first?.isWhitespace == false,
    range.lowerBound > text.startIndex, text[text.index(before: range.lowerBound)].isWhitespace
  {
    right = right.drop(while: \.isWhitespace)
  }
  return String(right)
}

/// Every range where `needle` occurs, overlapping ones included; none for an empty needle.
private func occurrences(of needle: String, in text: String) -> [Range<String.Index>] {
  guard !needle.isEmpty else { return [] }
  var found: [Range<String.Index>] = []
  var start = text.startIndex
  while start < text.endIndex, let range = text.range(of: needle, range: start..<text.endIndex) {
    found.append(range)
    start = text.index(after: range.lowerBound)
  }
  return found
}

/// Why proofreading gave no usable result. A `ModelError` is thrown as it is.
public enum ProofreadError: Error, Sendable, Equatable {
  /// The output limit cut the answer off.
  case truncated
  /// The provider's content filter stopped the answer.
  case refused
  /// The stream ended without a finish reason.
  case interrupted
  /// The answer is not the edit list.
  case malformed
  /// The edit list does not fit the source.
  case edits(EditError)
}

/// Decodes the model's `{"edits": […]}` answer.
public func decodeEdits(_ json: String) throws(ProofreadError) -> [Edit] {
  struct Answer: Decodable { let edits: [Edit] }
  do {
    return try JSONDecoder().decode(Answer.self, from: Data(json.utf8)).edits
  } catch {
    throw .malformed
  }
}

/// Proofreads with a `TextModel` and the prompt of `PromptBuilder.proofread`. The edit list
/// is used only when the answer is complete.
public struct Proofreader: Sendable {
  public let model: any TextModel
  public let makeNonce: @Sendable () -> String

  public init(
    model: any TextModel,
    makeNonce: @escaping @Sendable () -> String = { PromptBuilder.makeNonce() }
  ) {
    self.model = model
    self.makeNonce = makeNonce
  }

  /// The corrected text and its diff; no changes when there are no mistakes. Throws a
  /// `ModelError` or a `ProofreadError`. Cancelling the calling task cancels the request.
  public func proofread(_ text: String) async throws -> AppliedEdits {
    var received = ""
    var finish: FinishReason?
    for try await event in model.stream(PromptBuilder.proofread(text, nonce: makeNonce())) {
      switch event {
      case .thinking: break
      case .text(let delta): received += delta
      case .discardText: received = ""
      case .finished(let reason, _): finish = reason
      }
    }
    switch finish {
    case .complete: break
    case .truncated: throw ProofreadError.truncated
    case .refused: throw ProofreadError.refused
    case .unknown, nil: throw ProofreadError.interrupted
    }
    switch applyEdits(try decodeEdits(received), to: text) {
    case .success(let applied): return applied
    case .failure(let error): throw ProofreadError.edits(error)
    }
  }
}
