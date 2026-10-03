// SPDX-License-Identifier: GPL-3.0-or-later
//
// Prompt evaluation against real models (architecture 14.5). Not run in CI.
// Run through `make eval SUITE=<suite> RUNS=<n>`, which puts OPENAI_API_KEY in the environment.

import DictCore
import Foundation

let usage = """
  usage: DictEval --suite <\(suites.map(\.name).joined(separator: "|"))|all> [--runs <n>]
                  [--model <name>] [--price <input>,<output>] [--max-cost <dollars>]
                  [--threshold <0...1>]

    --runs       calls per case (default 10)
    --model      model id (default gpt-6-luna)
    --price      dollars per million input and output tokens, for models without a known price
    --max-cost   stop starting calls once this much has been spent (default 1)
    --threshold  minimum pass rate of every invariant (default 0.95)
  """

/// Dollars per million input and output tokens (architecture 6.8, OpenAI's price list).
let knownPrices = [
  "gpt-6-luna": EvalPrice(inputPerMillion: 0.10, outputPerMillion: 0.50),
  "gpt-6-sol": EvalPrice(inputPerMillion: 2.00, outputPerMillion: 10.00),
  "gpt-5-nano": EvalPrice(inputPerMillion: 0.05, outputPerMillion: 0.40),
]

struct Options {
  var suites: [Suite] = []
  var runs = 10
  var model = "gpt-6-luna"
  var price: EvalPrice?
  var maxCost = 1.0
  var threshold = 0.95
}

struct UsageError: Error {
  var message: String
}

func parseOptions(_ arguments: [String]) throws(UsageError) -> Options {
  var options = Options()
  var remaining = arguments[...]
  func value(for flag: String) throws(UsageError) -> String {
    guard let value = remaining.popFirst() else {
      throw UsageError(message: "\(flag) needs a value")
    }
    return value
  }
  func number(for flag: String) throws(UsageError) -> Double {
    let text = try value(for: flag)
    guard let number = Double(text), number >= 0 else {
      throw UsageError(message: "\(flag): not a number: \(text)")
    }
    return number
  }
  while let flag = remaining.popFirst() {
    switch flag {
    case "--suite":
      let name = try value(for: flag)
      options.suites = name == "all" ? suites : suites.filter { $0.name == name }
      if options.suites.isEmpty { throw UsageError(message: "unknown suite: \(name)") }
    case "--runs":
      let text = try value(for: flag)
      guard let runs = Int(text), runs > 0 else {
        throw UsageError(message: "--runs: not a positive integer: \(text)")
      }
      options.runs = runs
    case "--model":
      options.model = try value(for: flag)
    case "--price":
      let parts = try value(for: flag).split(separator: ",").compactMap { Double($0) }
      guard parts.count == 2 else {
        throw UsageError(message: "--price: expected <input>,<output>")
      }
      options.price = EvalPrice(inputPerMillion: parts[0], outputPerMillion: parts[1])
    case "--max-cost":
      options.maxCost = try number(for: flag)
    case "--threshold":
      options.threshold = try number(for: flag)
    case "--help", "-h":
      throw UsageError(message: "")
    default:
      throw UsageError(message: "unknown argument: \(flag)")
    }
  }
  if options.suites.isEmpty { throw UsageError(message: "--suite is required") }
  return options
}

/// The OpenAI client the app uses, with thinking off (`reasoning_effort: none` on gpt-6).
func makeModel(model: String, apiKey: String) throws(UsageError) -> any TextModel {
  let preset: ProviderPreset
  do {
    guard let openAI = try ProviderPreset.all().first(where: { $0.id == "openai" }) else {
      throw UsageError(message: "the preset table has no OpenAI row")
    }
    preset = openAI
  } catch let error as UsageError {
    throw error
  } catch {
    throw UsageError(message: "cannot read the preset table: \(error)")
  }
  return ChatCompletionsModel(
    endpoint: preset.endpoint(model: model, thinking: .off), rules: preset.thinkingRules,
    apiKey: apiKey)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("DictEval: \(message)\n".utf8))
  exit(2)
}

let options: Options
do {
  options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
} catch {
  fail(error.message.isEmpty ? usage : "\(error.message)\n\n\(usage)")
}

guard let price = options.price ?? knownPrices[options.model] else {
  fail("no known price for \(options.model); pass --price <input>,<output>")
}
guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
  fail("OPENAI_API_KEY is not set; run through `make eval`, which reads it from .env")
}

let model: any TextModel
do {
  model = try makeModel(model: options.model, apiKey: apiKey)
} catch {
  fail(error.message)
}

var allPassed = true
var spent = 0.0
for suite in options.suites {
  let runner = EvalRunner(model: model, price: price, costLimit: options.maxCost - spent)
  let report = await runner.run(suite.cases, runs: options.runs) { run in
    let passed = run.results.allSatisfy { $0.failure == nil }
    FileHandle.standardError.write(Data((passed ? "." : "x").utf8))
  }
  FileHandle.standardError.write(Data("\n".utf8))
  spent += report.cost
  print(report.rendered(title: "\(suite.name) · \(options.model)", threshold: options.threshold))
  print()
  allPassed = allPassed && report.passes(threshold: options.threshold)
}
print(allPassed ? "PASS" : "FAIL", "· total $\(String(format: "%.4f", spent))")
exit(allPassed ? 0 : 1)
