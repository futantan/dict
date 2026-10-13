// SPDX-License-Identifier: GPL-3.0-or-later

/// Where the text is going to be used; a trusted parameter of the improve and
/// translate-out prompts.
public enum AppContext: String, Sendable, Equatable { case chat, mail, document, code, other }

/// Maps an app to its context with a data table (architecture 5.3). Bundle ids compare
/// without case; an app not in the table, a browser among them, is `.other`.
public func appContext(bundleID: String?) -> AppContext {
  guard let bundleID else { return .other }
  return appContextsByKey[bundleID.lowercased()] ?? .other
}

/// The apps whose context is known, by bundle id. Browsers are left out: a page in one can
/// be a mail, a chat or a document.
let appContexts: [String: AppContext] = [
  // Mail
  "com.apple.mail": .mail,
  "com.microsoft.Outlook": .mail,
  "com.readdle.SparkDesktop": .mail,
  "com.readdle.smartemail-Mac": .mail,
  "com.mimestream.Mimestream": .mail,
  "it.bloop.airmail2": .mail,
  "org.mozilla.thunderbird": .mail,
  // Chat
  "com.tencent.xinWeChat": .chat,
  "com.tencent.WeWorkMac": .chat,
  "com.tencent.qq": .chat,
  "com.tinyspeck.slackmacgap": .chat,
  "com.hnc.Discord": .chat,
  "ru.keepcoder.Telegram": .chat,
  "org.telegram.desktop": .chat,
  "com.apple.MobileSMS": .chat,
  "net.whatsapp.WhatsApp": .chat,
  "org.whispersystems.signal-desktop": .chat,
  "com.microsoft.teams2": .chat,
  "com.alibaba.DingTalkMac": .chat,
  // Documents and notes
  "com.apple.iWork.Pages": .document,
  "com.apple.iWork.Keynote": .document,
  "com.microsoft.Word": .document,
  "com.microsoft.Powerpoint": .document,
  "com.apple.Notes": .document,
  "com.apple.TextEdit": .document,
  "notion.id": .document,
  "md.obsidian": .document,
  "net.shinyfrog.bear": .document,
  "com.lukilabs.lukiapp": .document,
  "com.ulyssesapp.mac": .document,
  "abnerworks.Typora": .document,
  // Code: editors and terminals
  "com.microsoft.VSCode": .code,
  "com.microsoft.VSCodeInsiders": .code,
  "com.apple.dt.Xcode": .code,
  "com.todesktop.230313mxl6dzkn9": .code,
  "com.exafunction.windsurf": .code,
  "dev.zed.Zed": .code,
  "com.sublimetext.4": .code,
  "com.panic.Nova": .code,
  "com.barebones.bbedit": .code,
  "com.apple.Terminal": .code,
  "com.googlecode.iterm2": .code,
  "com.mitchellh.ghostty": .code,
  "dev.warp.Warp-Stable": .code,
  "net.kovidgoyal.kitty": .code,
  "org.alacritty": .code,
  "com.github.wez.wezterm": .code,
]

private let appContextsByKey = Dictionary(
  uniqueKeysWithValues: appContexts.map { ($0.key.lowercased(), $0.value) })
