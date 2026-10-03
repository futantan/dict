// SPDX-License-Identifier: GPL-3.0-or-later

/// The default action of the Write key: `.translateOut` when the text is mostly in my
/// language, `.proofread` otherwise (architecture 5.3).
public func writeAction(for text: String, pair: LanguagePair) -> Capability {
  fatalError("writeAction is not implemented yet (M3)")
}
