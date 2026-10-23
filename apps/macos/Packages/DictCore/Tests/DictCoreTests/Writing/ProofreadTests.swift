// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

private func edit(_ wrong: String, _ right: String, _ kind: Edit.Kind = .spelling) -> Edit {
  Edit(kind: kind, wrong: wrong, right: right)
}

struct ApplyEditsTests {
  @Test func appliesEditsInSourceOrderWhateverTheListOrder() throws {
    let source = "Their going to the park tomorow."
    let applied = try applyEdits(
      [edit("tomorow", "tomorrow"), edit("Their going", "They're going", .grammar)], to: source
    ).get()
    #expect(applied.text == "They're going to the park tomorrow.")
    #expect(
      applied.segments == [
        .changed(from: "Their", to: "They're"),
        .unchanged(" going to the park "),
        .changed(from: "tomorow", to: "tomorrow"),
        .unchanged("."),
      ])
    #expect(applied.changeCount == 2)
  }

  /// A span longer than the mistake must not show its unchanged words as deleted and
  /// inserted again: the diff marks only what differs.
  @Test func theDiffMarksOnlyWhatChangedInsideALongSpan() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("tomorow", "tomorrow"), edit(", I think it will be fun.", ". I think it will be fun."),
      ],
      to: source
    ).get()
    #expect(applied.text == "Their going to the park tomorrow. I think it will be fun.")
    #expect(
      applied.segments == [
        .unchanged("Their going to the park "),
        .changed(from: "tomorow,", to: "tomorrow."),
        .unchanged(" I think it will be fun."),
      ])
  }

  @Test func noEditsLeavesTheTextUnchanged() throws {
    let applied = try applyEdits([], to: "All good.").get()
    #expect(applied.text == "All good.")
    #expect(applied.segments == [.unchanged("All good.")])
    #expect(applied.changeCount == 0)
  }

  @Test func editsThatChangeNothingAreDropped() throws {
    let applied = try applyEdits([edit("good", "good")], to: "All good.").get()
    #expect(applied.changeCount == 0)
    #expect(applied.text == "All good.")
  }

  @Test func aSpanThatIsNotInTheSourceFails() {
    #expect(
      applyEdits([edit("x", "y"), edit("cat", "dog")], to: "a x") == .failure(.notFound(index: 1)))
    #expect(applyEdits([edit("", "y")], to: "a x") == .failure(.notFound(index: 0)))
  }

  @Test func aSpanThatOccursTwiceFails() {
    #expect(
      applyEdits([edit("teh", "the")], to: "teh cat and teh dog") == .failure(.ambiguous(index: 0)))
  }

  /// Overlapping occurrences count: "aa" occurs twice in "aaa".
  @Test func overlappingOccurrencesOfOneSpanCountAsAmbiguous() {
    #expect(applyEdits([edit("aa", "b")], to: "aaa") == .failure(.ambiguous(index: 0)))
  }

  /// Measured with gpt-6-luna, 3 of 3 runs: a later edit quotes the text as corrected by an
  /// earlier one ("tomorrow, I" after "tomorow" → "tomorrow"). Such a list is applied in
  /// order instead, and the diff comes from comparing the texts.
  @Test func editsThatBuildOnEachOtherAreAppliedInOrder() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("tomorrow, I think", "tomorrow. I think", .punctuation),
      ], to: source
    ).get()
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
    #expect(
      applied.segments == [
        .changed(from: "Their", to: "They're"),
        .unchanged(" going to the park "),
        .changed(from: "tomorow,", to: "tomorrow."),
        .unchanged(" I think it will be fun."),
      ])
  }

  @Test func inOrderASpanStillHasToOccurOnce() {
    #expect(
      applyEdits([edit("cat", "dog dog"), edit("dog", "x")], to: "a cat")
        == .failure(.ambiguous(index: 1)))
    #expect(
      applyEdits([edit("cat", "dog"), edit("bird", "x")], to: "a cat")
        == .failure(.notFound(index: 1)))
  }

  @Test func twoEditsWhoseSpansOverlapFail() {
    let source = "I has went home."
    #expect(
      applyEdits([edit("has went", "went"), edit("went home", "gone home")], to: source)
        == .failure(.overlapping(0, 1)))
  }

  /// Measured with gpt-6-luna: one edit's span contains another's ("park tomorow, I"
  /// around "tomorow"). The longer edit goes first and the shorter one then fixes the word
  /// inside its result.
  @Test func anEditInsideAnotherIsAppliedAfterIt() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("park tomorow, I", "park tomorow. I", .punctuation),
      ], to: source
    ).get()
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
  }

  /// Measured with gpt-6-luna (retest C15b, run 13): the punctuation edit's span contains
  /// the spelling edit's and already makes the same fix, so the spelling edit is dropped.
  @Test func anEditAlreadyMadeByALargerOneIsDropped() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("park tomorow,", "park tomorrow.", .punctuation),
      ], to: source
    ).get()
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
  }

  /// A larger span that does not make the smaller edit's fix is a real conflict.
  @Test func aLargerEditThatDisagreesStillOverlaps() {
    #expect(
      applyEdits(
        [edit("tomorow", "tomorrow"), edit("tomorow,", "tomorrw.")], to: "See you tomorow, ok")
        == .failure(.overlapping(0, 1)))
  }

  @Test func repeatedEditsCountOnce() throws {
    let applied = try applyEdits(
      [edit("tomorow", "tomorrow"), edit("tomorow", "tomorrow")], to: "See you tomorow."
    ).get()
    #expect(applied.text == "See you tomorrow.")
    #expect(applied.changeCount == 1)
  }

  /// Measured with gpt-6-luna: "right" sometimes ends in a space the text already has.
  @Test func aSpaceTheTextAlreadyHasIsNotDoubled() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("park tomorow,", "park tomorrow. ", .punctuation),
      ], to: source
    ).get()
    #expect(applied.text == "They're going to the park tomorrow. I think it will be fun.")
    // The in-order path trims the same way.
    let chained = try applyEdits(
      [edit("tomorow", "tomorrow"), edit("tomorrow,", "tomorrow. ", .punctuation)], to: source
    ).get()
    #expect(chained.text == "Their going to the park tomorrow. I think it will be fun.")
    #expect(applyEdits([edit("x", " y")], to: "a x").map(\.text) == .success("a y"))
  }

  @Test func spacesTheTextNeedsAreKept() throws {
    #expect(applyEdits([edit("x ", "z ")], to: "x  y").map(\.text) == .success("z  y"))
    #expect(
      applyEdits([edit("end.", "end. ")], to: "the end.Next").map(\.text)
        == .success("the end. Next"))
    #expect(applyEdits([edit("x", " y")], to: "ax").map(\.text) == .success("a y"))
  }

  @Test func keepsLineBreaksAndOtherCharactersExactly() throws {
    let source = "Hi Sam,\n\nI recieved it 👍\nhttps://x.y/z"
    let applied = try applyEdits([edit("recieved", "received")], to: source).get()
    #expect(applied.text == "Hi Sam,\n\nI received it 👍\nhttps://x.y/z")
  }
}

struct ProofreadDecodingTests {
  @Test func decodesTheEditList() throws {
    let json = #"{"edits":[{"kind":"word_form","wrong":"has went","right":"has gone"}]}"#
    #expect(try decodeEdits(json) == [Edit(kind: .wordForm, wrong: "has went", right: "has gone")])
  }

  @Test func rejectsAnythingElse() {
    #expect(throws: ProofreadError.malformed) { try decodeEdits("Sure! Here are the edits") }
    #expect(throws: ProofreadError.malformed) { try decodeEdits(#"{"edits":[{"kind":"style"}]}"#) }
  }
}
