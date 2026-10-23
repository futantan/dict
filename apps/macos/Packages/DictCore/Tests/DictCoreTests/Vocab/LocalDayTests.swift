// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import DictCore

struct LocalDayTests {
  @Test(arguments: ["2026-10-09", "2024-02-29", "0001-01-01", "9999-12-31"])
  func roundTrips(text: String) throws {
    let day = try #require(LocalDay(text))
    #expect(day.description == text)
  }

  @Test(arguments: [
    "", "2026-1-09", "2026-10-9", "26-10-09", "2026/10/09", "2026-13-01", "2026-02-29",
    "2026-00-10", "2026-10-00", "0000-01-01", " 2026-10-09", "2026-10-09T00", "２０２６-10-09",
    "+026-10-09",
  ])
  func rejects(text: String) {
    #expect(LocalDay(text) == nil)
  }

  @Test(arguments: [
    ("2026-10-09", 1, "2026-10-10"),
    ("2026-10-31", 1, "2026-11-01"),
    ("2026-12-31", 1, "2027-01-01"),
    ("2024-02-28", 1, "2024-02-29"),
    ("2025-02-28", 1, "2025-03-01"),
    ("2026-03-01", -1, "2026-02-28"),
    ("2026-10-09", 60, "2026-12-08"),
    ("2026-10-09", 0, "2026-10-09"),
  ])
  func addsDays(start: String, days: Int, expected: String) throws {
    let day = try #require(LocalDay(start))
    #expect(day.adding(days: days).description == expected)
  }

  @Test func ordersByDate() throws {
    let days = try ["2026-10-09", "2025-12-31", "2026-01-10", "2026-10-08"].map {
      try #require(LocalDay($0))
    }
    #expect(
      days.sorted().map(\.description) == [
        "2025-12-31", "2026-01-10", "2026-10-08", "2026-10-09",
      ])
  }

  @Test func takesTheDateInTheGivenTimeZone() throws {
    // 2026-10-09 23:30 in UTC is already the 10th in Sydney and still the 9th in Los Angeles.
    let date = Date(timeIntervalSince1970: 1_791_588_600)
    let sydney = try #require(TimeZone(identifier: "Australia/Sydney"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(LocalDay(date, in: .gmt).description == "2026-10-09")
    #expect(LocalDay(date, in: sydney).description == "2026-10-10")
    #expect(LocalDay(date, in: losAngeles).description == "2026-10-09")
  }
}
