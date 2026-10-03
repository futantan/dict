// SPDX-License-Identifier: GPL-3.0-or-later

import Testing

@testable import DictCore

private struct OtherError: Error {}

struct TranslationRecoveryTests {
  @Test(arguments: [
    // (error, has text, Apple supports the pair, expected)
    (ModelError.network(code: -1009) as any Error, false, true, TranslationRecovery.fallBack),
    (ModelError.network(code: -1009), true, true, .fallBack),
    (ModelError.missingKey, false, true, .fallBack),
    (ModelError.timedOut(.firstEvent), false, true, .fallBack),
    (ModelError.unauthorized, false, true, .fallBack),
    (ModelError.rateLimited(retryAfter: nil), false, true, .fallBack),
    (ModelError.server(status: 503), false, true, .fallBack),
    (ModelError.emptyResponse, false, true, .fallBack),
    (ModelTranslationError.refused, false, true, .fallBack),
    (ModelTranslationError.interrupted, true, true, .fallBack),
    (OtherError(), false, true, .fallBack),
    // Without Apple Translation the error is shown
    (ModelError.network(code: -1009), false, false, .showError),
    (ModelTranslationError.refused, false, false, .showError),
    (OtherError(), false, false, .showError),
    // A cut-off translation is still worth reading
    (ModelTranslationError.truncated, true, true, .keepPartial),
    (ModelTranslationError.truncated, true, false, .keepPartial),
    (ModelTranslationError.truncated, false, true, .fallBack),
    (ModelTranslationError.truncated, false, false, .showError),
    // Cancelling ends the session: nothing more is shown
    (CancellationError(), false, true, .stop),
    (CancellationError(), true, false, .stop),
  ])
  func decision(error: any Error, hasText: Bool, apple: Bool, expected: TranslationRecovery) {
    #expect(
      translationRecovery(after: error, hasText: hasText, appleTranslationSupportsPair: apple)
        == expected)
  }
}
