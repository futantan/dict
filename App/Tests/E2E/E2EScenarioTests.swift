// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
  import Foundation
  import Testing

  @testable import DictApp

  struct E2EScenarioTests {
    @Test func parsesEveryStepKind() throws {
      let json = """
        {"steps": [
          {"select": {"control": "textView.plain", "text": "Hello"}},
          {"wait": {"ms": 250}},
          {"capture": {"policy": "never"}},
          {"capture": {"policy": "allowed"}},
          {"read": {}},
          {"read": {"force": "key"}},
          {"read": {"force": "paste"}},
          {"unknown": {}}
        ]}
        """
      let steps = try E2EScenario.parse(Data(json.utf8))
      #expect(
        steps == [
          .select(control: "textView.plain", text: "Hello"),
          .wait(ms: 250),
          .capture(.never),
          .capture(.allowed),
          .read(force: nil),
          .read(force: .key),
          .invalid("read force must be menu or key"),
          .invalid("unknown step"),
        ])
    }

    @Test func rejectsAFileWithoutSteps() {
      #expect(throws: (any Error).self) { try E2EScenario.parse(Data("{}".utf8)) }
    }

    @Test func encodesASuccessfulCapture() throws {
      let row = E2EResultRow.capture(
        ms: 12.5,
        result: .success(
          Selection(
            text: "Hello", source: .accessibility, app: nil, bounds: nil, context: nil,
            target: nil)))
      let object = try #require(row.json as? [String: Any])
      #expect(object["step"] as? String == "capture")
      #expect(object["ok"] as? Bool == true)
      #expect(object["ms"] as? Double == 12.5)
      #expect(object["source"] as? String == "accessibility")
      #expect(object["text"] as? String == "Hello")
      #expect(object["failure"] is NSNull)
    }

    @Test func encodesAFailureByCaseName() throws {
      let row = E2EResultRow.capture(ms: 3, result: .failure(.nothingSelected(fieldText: "x")))
      let object = try #require(row.json as? [String: Any])
      #expect(object["ok"] as? Bool == false)
      #expect(object["failure"] as? String == "nothingSelected")
      #expect(object["source"] is NSNull)
      #expect(object["text"] is NSNull)
    }

    @Test func failureNamesAreBareCaseNames() {
      #expect(CaptureFailure.secureInput(holder: "Ghostty").caseName == "secureInput")
      #expect(CaptureFailure.unreadable(axError: -25212).caseName == "unreadable")
      #expect(CaptureFailure.noAccessibilityPermission.caseName == "noAccessibilityPermission")
      #expect(CaptureSource.menuCopy.caseName == "menuCopy")
    }

    @Test func writesTheResultFileAsJSON() throws {
      let rows = [E2EResultRow.wait(ms: 10), .capture(ms: 1, result: .failure(.ownApp))]
      let data = try E2EResultRow.document(rows)
      let object = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any])
      let steps = try #require(object["steps"] as? [[String: Any]])
      #expect(steps.count == 2)
      #expect(steps[0]["step"] as? String == "wait")
      #expect(steps[1]["failure"] as? String == "ownApp")
    }
  }
#endif
