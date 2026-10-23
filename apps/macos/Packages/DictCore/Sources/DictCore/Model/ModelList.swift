// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why a model list could not be read, besides a `ModelError`.
public enum ModelListError: Error, Sendable, Equatable {
  /// The service answered 404 or 405: it has no list endpoint at this address.
  case unsupported
}

/// Where `style` lists the models of the service at `baseURL`. Ollama's tags live at the
/// server root, outside its OpenAI-compatible `/v1`.
public func modelListURL(baseURL: URL, style: ModelListStyle) -> URL {
  switch style {
  case .openAI:
    return baseURL.appending(path: "models")
  case .ollama:
    var root = baseURL
    if root.lastPathComponent == "v1" { root.deleteLastPathComponent() }
    return root.appending(path: "api/tags")
  }
}

/// The model names in a list response, sorted and without duplicates: `data[].id` for an
/// OpenAI-compatible service, `models[].name` (or `.model`) for Ollama. Throws
/// `ModelError.malformedResponse` for any other shape.
public func decodeModelList(_ data: Data, style: ModelListStyle) throws(ModelError) -> [String] {
  guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
    throw .malformedResponse
  }
  let items: [JSONValue]?
  let names: (JSONValue) -> String?
  switch style {
  case .openAI:
    items = json["data"]?.arrayValue
    names = { $0["id"]?.stringValue }
  case .ollama:
    items = json["models"]?.arrayValue
    names = { $0["name"]?.stringValue ?? $0["model"]?.stringValue }
  }
  guard let items else { throw .malformedResponse }
  return Set(items.compactMap(names).filter { !$0.isEmpty }).sorted()
}

/// Lists the models the service at `endpoint` offers; the endpoint's model is ignored.
///
/// Throws a `ModelError` (mapped like a chat request, key masked), or
/// `ModelListError.unsupported`. Cancelling the calling task cancels the request.
public func listModels(
  _ endpoint: ModelEndpoint, style: ModelListStyle, apiKey: String?,
  session: URLSession = .shared, timeout: TimeInterval = 15
) async throws -> [String] {
  if endpoint.auth != .none && (apiKey ?? "").isEmpty { throw ModelError.missingKey }
  var request = URLRequest(url: modelListURL(baseURL: endpoint.baseURL, style: style))
  request.httpMethod = "GET"
  request.timeoutInterval = timeout
  request.setValue("application/json", forHTTPHeaderField: "Accept")
  endpoint.authorize(&request, apiKey: apiKey)

  let data: Data
  let response: URLResponse
  do {
    (data, response) = try await session.data(for: request)
  } catch let error as URLError {
    if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
    if error.code == .timedOut { throw ModelError.timedOut(.total) }
    throw ModelError.network(code: error.code.rawValue)
  }
  guard let http = response as? HTTPURLResponse else { throw ModelError.malformedResponse }
  switch http.statusCode {
  case 200..<300: return try decodeModelList(data, style: style)
  case 404, 405: throw ModelListError.unsupported
  default: throw httpFailure(data, http, apiKey: apiKey).error
  }
}
