// SPDX-License-Identifier: GPL-3.0-or-later
//
// Table-driven checks of the matrix row's pure parts, run by `dict-driver check` (no apps).

/// Returns the failed checks; empty when every check passes.
func matrixRowProblems() -> [String] {
  let context = "It was a bright cold day in April."
  let cases:
    [(name: String, expect: String?, ok: Bool, source: String?, got: String?, cell: String)] = [
      ("matching context", context, true, "accessibility", context, "PASS"),
      ("different context", context, true, "accessibility", "It was a bright", "FAIL"),
      ("missing context", context, true, "accessibility", nil, "FAIL"),
      ("menu copy has none", context, true, "menuCopy", nil, "—"),
      ("key copy has none", context, true, "keyCopy", nil, "—"),
      ("copy with a context", context, true, "keyCopy", context, "FAIL"),
      ("failed capture", context, false, nil, nil, "—"),
      ("no expectation", nil, true, "accessibility", "Anything.", "—"),
    ]
  var problems: [String] = []
  for test in cases {
    let cell = MatrixRow.contextCell(
      expect: test.expect, ok: test.ok, source: test.source, got: test.got)
    if cell != test.cell { problems.append("\(test.name): got \(cell), expected \(test.cell)") }
  }

  var row = MatrixRow(app: "Safari", control: "web.paragraph", state: "first")
  row.ok = true
  row.source = "accessibility"
  row.textMatches = true
  row.context = context
  row.contextCheck = "PASS"
  row.ms = 12.34
  row.clipboardIntact = true
  let line =
    "Safari | web.paragraph | first: accessibility text ok, context PASS, 12.3 ms, clipboard ok"
  if row.line != line { problems.append("line: got \(row.line)") }
  let decoded = MatrixRow(json: row.json)
  if decoded.comparable != row.comparable || decoded.context != row.context {
    problems.append("json round trip changes \(row.comparable)")
  }
  return problems
}
