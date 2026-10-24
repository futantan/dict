// SPDX-License-Identifier: GPL-3.0-or-later

/// Builds the Responses request body for the ChatGPT plan (docs/reviews/chatgpt-login.md
/// 4.4). The plan requires `store: false` and `stream: true`, takes the system prompt as
/// `instructions` (it rejects system-role input), and rejects `max_output_tokens`,
/// `temperature` and other sampling or tracking fields, so none of them is ever sent;
/// `request.maxOutputTokens` goes unused.
///
/// `reasoning.effort` (from the preset's thinking rules) and the strict `json_schema` format
/// are not documented either way for the plan; they are sent as on the OpenAI API, and a
/// rejection surfaces as `ModelError.badRequest` with the server's message.
public func responsesBody(
  _ request: ModelRequest, model: String, thinking: ThinkingSetting, rules: [ThinkingRule]
) -> JSONValue {
  var body: JSONObject = ["model": .string(model)]
  if !request.system.isEmpty { body["instructions"] = .string(request.system) }
  body["input"] = [["role": "user", "content": .string(request.user)]]
  body["store"] = false
  body["stream"] = true
  if case .object(let fragment) = thinkingFragment(for: model, setting: thinking, rules: rules) {
    body.merge(fragment)
  }
  if case .jsonSchema(let name, let schema) = request.output {
    body["text"] = [
      "format": ["type": "json_schema", "name": .string(name), "strict": true, "schema": schema]
    ]
  }
  return .object(body)
}
