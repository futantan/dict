// SPDX-License-Identifier: GPL-3.0-or-later

/// The seam between the app and a model provider (architecture 6.1).
public protocol TextModel: Sendable {
  /// Starts one request per call. Cancelling the consuming task cancels the network request.
  func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, Error>
}
