// SPDX-License-Identifier: GPL-3.0-or-later

/// Builds the complete Chat Completions request body sent to the provider (architecture 6.2).
public func requestBody(
  _ request: ModelRequest, endpoint: ModelEndpoint, rules: [ThinkingRule]
) -> JSONValue {
  var messages: [JSONValue] = []
  if !request.system.isEmpty {
    messages.append(["role": "system", "content": .string(request.system)])
  }
  messages.append(["role": "user", "content": .string(request.user)])

  var body: JSONObject = [
    "model": .string(endpoint.model),
    "messages": .array(messages),
    "stream": true,
    "stream_options": ["include_usage": true],
    endpoint.tokenLimitField: .number(Double(request.maxOutputTokens)),
  ]
  if case .object(let fragment) = thinkingFragment(
    for: endpoint.model, setting: endpoint.thinking, rules: rules)
  {
    body.merge(fragment)
  }
  if let format = responseFormat(request.output, mode: endpoint.jsonMode) {
    body["response_format"] = format
  }
  return .object(body)
}

private func responseFormat(_ output: OutputFormat, mode: JSONMode) -> JSONValue? {
  guard case .jsonSchema(let name, let schema) = output else { return nil }
  switch mode {
  case .schema:
    return [
      "type": "json_schema",
      "json_schema": ["name": .string(name), "strict": true, "schema": schema],
    ]
  case .object: return ["type": "json_object"]
  case .none: return nil
  }
}
