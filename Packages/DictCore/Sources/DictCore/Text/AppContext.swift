// SPDX-License-Identifier: GPL-3.0-or-later

/// Where the text is going to be used; a trusted parameter of the improve and
/// translate-out prompts.
public enum AppContext: String, Sendable, Equatable { case chat, mail, document, code, other }

/// Maps an app to its context with a data table (architecture 5.3).
public func appContext(bundleID: String?) -> AppContext {
  fatalError("appContext is not implemented yet (M3)")
}
