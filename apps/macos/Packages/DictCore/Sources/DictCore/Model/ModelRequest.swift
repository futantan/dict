// SPDX-License-Identifier: GPL-3.0-or-later

/// Plain text, or JSON constrained by a strict schema.
public enum OutputFormat: Sendable, Equatable {
  case text
  case jsonSchema(name: String, schema: JSONValue)
}

/// One model call: the prompts and the output contract.
public struct ModelRequest: Sendable, Equatable {
  public var system: String
  public var user: String
  public var output: OutputFormat
  public var maxOutputTokens: Int

  public init(system: String, user: String, output: OutputFormat, maxOutputTokens: Int) {
    self.system = system
    self.user = user
    self.output = output
    self.maxOutputTokens = maxOutputTokens
  }
}

/// What a streaming call yields.
public enum StreamEvent: Sendable, Equatable {
  /// A thinking delta: only drives the "thinking" indicator and feeds the watchdog.
  case thinking
  /// A delta of the answer text.
  case text(String)
  /// Thinking leaked into the answer (an unopened `</think>` arrived): drop all text received
  /// so far; the answer continues with the next `.text`.
  case discardText
  case finished(FinishReason, Usage?)
}

/// Why the stream ended. Only `.complete` results may be used for replacement.
public enum FinishReason: Sendable, Equatable { case complete, truncated, refused, unknown }

/// Token counts reported by the provider.
public struct Usage: Sendable, Equatable {
  public var inputTokens: Int
  public var outputTokens: Int

  public init(inputTokens: Int, outputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}

/// Why a model call failed.
public enum ModelError: Error, Sendable, Equatable {
  case missingKey
  /// HTTP 401 or 403.
  case unauthorized
  /// HTTP 404.
  case modelNotFound
  /// HTTP 429.
  case rateLimited(retryAfter: Duration?)
  /// HTTP 400.
  case badRequest(message: String)
  /// HTTP 5xx.
  case server(status: Int)
  /// A URLError code.
  case network(code: Int)
  case timedOut(TimeoutStage)
  case emptyResponse
  case malformedResponse
  /// ChatGPT: no account is signed in, or the sign-in ended (a refresh was refused).
  case signInRequired
  /// ChatGPT: signed in, but the user did not let this app use their plan.
  case planUsageNotGranted
  /// ChatGPT: the account, workspace or region may not use its plan here (HTTP 403).
  case planNotEligible
  /// ChatGPT: the plan's usage, or this app's limit in the ChatGPT settings, is used up.
  case planLimitReached
}

/// Which watchdog fired.
public enum TimeoutStage: Sendable, Equatable { case firstEvent, idle, total }
