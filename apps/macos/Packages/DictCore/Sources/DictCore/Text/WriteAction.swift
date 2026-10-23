// SPDX-License-Identifier: GPL-3.0-or-later

/// The default action of the Write key (architecture 5.3): `.translateOut` exactly when
/// `resolveDirection` would translate the text into the learning language, `.proofread`
/// otherwise. So "mostly my language" follows the same rules as reading: at least a third of
/// the letters in my script when the scripts differ (mixed text such as
/// "这个 PR 我已经 review 过了" is translated out), the language recognizer when they are the
/// same. Text in the learning language or a third language, and text without letters, is
/// proofread, which never changes its language.
public func writeAction(for text: String, pair: LanguagePair) -> Capability {
  resolveDirection(text, pair: pair) == .intoLearning ? .translateOut : .proofread
}
