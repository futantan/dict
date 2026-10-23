// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

private func edit(_ wrong: String, _ right: String, _ kind: Edit.Kind = .spelling) -> Edit {
  Edit(kind: kind, wrong: wrong, right: right)
}

/// Every subset of `count` change indices.
private func subsets(of count: Int) -> [Set<Int>] {
  (0..<(1 << count)).map { mask in Set((0..<count).filter { mask & (1 << $0) != 0 }) }
}

/// Undoing changes the user declined (architecture 6.7): the unit is a change of the diff,
/// what the panel shows, not an edit of the model's list.
struct AcceptingTests {
  private let source = "Their going to the park tomorow."

  private func applied() throws -> AppliedEdits {
    try applyEdits(
      [edit("tomorow", "tomorrow"), edit("Their going", "They're going", .grammar)], to: source
    ).get()
  }

  @Test func acceptingEveryChangeIsTheFullCorrection() throws {
    let applied = try applied()
    #expect(applied.accepting([0, 1]) == applied)
    #expect(applied.accepting(Set(0..<applied.changeCount)) == applied)
  }

  @Test func acceptingNoChangeGivesTheSourceBack() throws {
    let none = try applied().accepting([])
    #expect(none.text == source)
    #expect(none.segments == [.unchanged(source)])
    #expect(none.changeCount == 0)
  }

  @Test func aDeclinedChangeTurnsBackIntoTheSource() throws {
    let first = try applied().accepting([1])
    #expect(first.text == "Their going to the park tomorrow.")
    #expect(
      first.segments == [
        .unchanged("Their going to the park "),
        .changed(from: "tomorow", to: "tomorrow"),
        .unchanged("."),
      ])
    let second = try applied().accepting([0])
    #expect(second.text == "They're going to the park tomorow.")
    #expect(second.changeCount == 1)
  }

  @Test func indicesThatAreNoChangeAreIgnored() throws {
    let applied = try applied()
    #expect(applied.accepting([0, 1, 2, -1]) == applied)
    #expect(applied.accepting([7]).text == source)
  }

  /// Two changes with the same text are told apart by position, so declining one keeps
  /// the other.
  @Test func changesWithTheSameTextAreDeclinedOneByOne() throws {
    let applied = try applyEdits(
      [edit("teh cat", "the cat"), edit("teh dog", "the dog")], to: "teh cat and teh dog"
    ).get()
    #expect(applied.changeCount == 2)
    #expect(applied.accepting([0]).text == "the cat and teh dog")
    #expect(applied.accepting([1]).text == "teh cat and the dog")
  }

  /// Overlapping edits (one span inside another) end up in one change of the diff, which
  /// is accepted or declined whole.
  @Test func overlappingEditsAreOneChange() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("park tomorow, I", "park tomorow. I", .punctuation),
      ],
      to: source
    ).get()
    #expect(applied.changeCount == 2)
    #expect(
      applied.accepting([1]).text == "Their going to the park tomorrow. I think it will be fun.")
    #expect(
      applied.accepting([0]).text == "They're going to the park tomorow, I think it will be fun.")
  }

  /// Edits that build on each other are applied in order; each of their changes can still
  /// be declined on its own.
  @Test func chainedEditsCanBeDeclinedOneByOne() throws {
    let source = "Their going to the park tomorow, I think it will be fun."
    let applied = try applyEdits(
      [
        edit("Their", "They're", .wordForm), edit("tomorow", "tomorrow"),
        edit("tomorrow, I", "tomorrow. I", .punctuation),
      ],
      to: source
    ).get()
    #expect(applied.accepting([]).text == source)
    #expect(
      applied.accepting([0]).text == "They're going to the park tomorow, I think it will be fun.")
  }

  /// The diff's invariant this rests on: its unchanged runs with the `from` sides give the
  /// source, with the `to` sides the text, for every subset in between. Includes trimmed
  /// whitespace and Chinese.
  @Test(arguments: [
    (
      "Their going to the park tomorow, I think it will be fun.",
      [
        edit("Their", "They're", .wordForm), edit("park tomorow,", "park tomorrow. ", .punctuation),
      ]
    ),
    (
      "She have lived here for 2019 and work at bakery.",
      [
        edit("have", "has"), edit("for 2019", "since 2019"),
        edit("work at bakery", "works at a bakery"),
      ]
    ),
    ("我今天很高心，明天在见。", [edit("高心", "高兴"), edit("在见", "再见")]),
  ])
  func everySubsetLiesBetweenTheSourceAndTheCorrection(source: String, edits: [Edit]) throws {
    let applied = try applyEdits(edits, to: source).get()
    #expect(applied.accepting([]).text == source)
    #expect(applied.accepting(Set(0..<applied.changeCount)).text == applied.text)
    for accepted in subsets(of: applied.changeCount) {
      let partial = applied.accepting(accepted)
      #expect(partial.changeCount == accepted.count)
      let from = partial.segments.map {
        switch $0 {
        case .unchanged(let run): run
        case .changed(let from, _): from
        }
      }
      #expect(from.joined() == source)
    }
  }
}
