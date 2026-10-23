// SPDX-License-Identifier: GPL-3.0-or-later

extension AppliedEdits {
  /// The correction with only the changes in `accepted` made (architecture 6.7). A change
  /// is a `.changed` run of `segments`, counted from 0 in order; the declined ones turn back
  /// into the source and join the unchanged text around them. Indices that are no change
  /// are ignored.
  ///
  /// The unit is the diff's change, not the model's edit: edits can be absorbed by others,
  /// applied in a chain or one inside another, and the diff merges neighbouring ones, so a
  /// change is what the user sees and what can always be undone on its own. Accepting every
  /// change gives `self`, accepting none gives the source.
  public func accepting(_ accepted: Set<Int>) -> AppliedEdits {
    var kept: [DiffSegment] = []
    var change = 0
    func appendUnchanged(_ run: String) {
      guard !run.isEmpty else { return }
      if case .unchanged(let before) = kept.last {
        kept[kept.count - 1] = .unchanged(before + run)
      } else {
        kept.append(.unchanged(run))
      }
    }
    for segment in segments {
      switch segment {
      case .unchanged(let run):
        appendUnchanged(run)
      case .changed(let from, _) where !accepted.contains(change):
        appendUnchanged(from)
        change += 1
      case .changed:
        kept.append(segment)
        change += 1
      }
    }
    let text = kept.map {
      switch $0 {
      case .unchanged(let run): run
      case .changed(_, let to): to
      }
    }
    return AppliedEdits(text: text.joined(), segments: kept)
  }
}
