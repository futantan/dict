// SPDX-License-Identifier: GPL-3.0-or-later
//
// dict-driver: the end-to-end test driver behind scripts/e2e.sh, scripts/matrix.sh and
// scripts/e2e-selftest.sh. Built by scripts/build-driver.sh.
//
//   dict-driver e2e      --app <Dict.app> --fixture <CaptureFixture.app> --scenarios <json> --work <dir>
//   dict-driver matrix   --app <Dict.app> --pages <dir> --out <json> --work <dir> [--only a,b]
//   dict-driver selftest --fixture <CaptureFixture.app> --fakes <dir> --work <dir>
//
// Exit status: 0 all passed, 1 failures, 2 skipped because the app has no `--e2e` entry point
// yet, 3 usage or environment errors.

import AppKit
import ApplicationServices

func option(_ name: String) -> String? {
  let arguments = CommandLine.arguments
  guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else {
    return nil
  }
  return arguments[index + 1]
}

func required(_ name: String) throws -> URL {
  guard let value = option(name) else { throw DriverError("missing --\(name)") }
  return URL(fileURLWithPath: value)
}

func requireAccessibility() throws {
  guard AXIsProcessTrusted() else {
    throw DriverError(
      "this terminal lacks Accessibility permission; the driver does not change system settings")
  }
}

@MainActor
func main() -> Int32 {
  Cleanup.installSignalHandlers()
  defer { Cleanup.runAll() }
  let command = CommandLine.arguments.dropFirst().first ?? ""
  do {
    switch command {
    case "e2e":
      let e2e = E2E(
        app: try required("app"), fixtureApp: try required("fixture"),
        scenarios: try E2E.loadScenarios(try required("scenarios")),
        workDirectory: try required("work"))
      say("e2e: app under test \(e2e.app.lastPathComponent), \(e2e.scenarios.count) scenarios")
      let report = try e2e.run()
      say("e2e: --e2e entry point \(report.entryPoint)")
      if report.entryPoint != "present" { report.outcomes.forEach { say($0.line) } }
      say("e2e: \(report.summary)")
      if report.passed { return 0 }
      return report.count(.skip) > 0 && report.count(.fail) == 0 ? 2 : 1

    case "matrix":
      try requireAccessibility()
      let only = option("only").map { $0.split(separator: ",").map(String.init) }
      var matrix = Matrix(
        app: try required("app"), pages: try required("pages"), output: try required("out"),
        work: try required("work"), only: only)
      return try matrix.run()

    case "selftest":
      try requireAccessibility()
      let passed = try SelfTest().run(
        fixtureApp: try required("fixture"), fakes: try required("fakes"),
        work: try required("work"))
      return passed ? 0 : 1

    default:
      throw DriverError("usage: dict-driver e2e|matrix|selftest … (see scripts/driver/main.swift)")
    }
  } catch {
    say("driver: error: \(error)")
    return 3
  }
}

exit(main())
