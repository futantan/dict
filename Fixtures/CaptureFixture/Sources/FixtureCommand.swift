// SPDX-License-Identifier: GPL-3.0-or-later
//
// The fixture's command channel (Design/m1-tasks.md, end-to-end interface): the distributed
// notification `au.ibra.dict.fixture.command` with a userInfo of
// `{"command": "select", "control": "<id>", "text": "…"}`.
// The optional `content` key replaces the control's text before selecting, so a driver can
// set both the text and the selection.

import Foundation

struct FixtureCommand: Equatable {
  static let notificationName = Notification.Name("au.ibra.dict.fixture.command")

  var control: String
  /// The text to select; the first occurrence in the control's content.
  var text: String
  /// Replaces the control's content first when present.
  var content: String?

  init(control: String, text: String, content: String? = nil) {
    self.control = control
    self.text = text
    self.content = content
  }

  init?(userInfo: [AnyHashable: Any]?) {
    guard let userInfo, userInfo["command"] as? String == "select",
      let control = userInfo["control"] as? String
    else { return nil }
    self.init(
      control: control, text: userInfo["text"] as? String ?? "",
      content: userInfo["content"] as? String)
  }
}

/// Control identifiers, which are also the accessibility identifiers.
enum ControlID {
  static let plainTextView = "textView.plain"
  static let richTextView = "textView.rich"
  /// A rich text view whose content is light markup: `**bold**` and `[text](url)`.
  static let formattedTextView = "textView.formatted"
  static let textField = "textField"
  static let secureField = "secureField"
  static let webParagraph = "web.paragraph"
  static let webTextarea = "web.textarea"
  static let webContentEditable = "web.contenteditable"
  static let customNoSelectedText = "custom.noSelectedText"
  static let customEmpty = "custom.empty"
  static let customCopiesLine = "custom.copiesLine"

  static let web = [webParagraph, webTextarea, webContentEditable]
}

/// The UTF-16 range of the first occurrence of `text` in `content`.
/// An empty `text` gives an empty range at the start; a missing one gives nil.
func selectionRange(of text: String, in content: String) -> NSRange? {
  guard !text.isEmpty else { return NSRange(location: 0, length: 0) }
  let range = (content as NSString).range(of: text)
  return range.location == NSNotFound ? nil : range
}
