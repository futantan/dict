import { cleanup, render, screen, within } from "@testing-library/react"
import { afterEach, describe, expect, it } from "vitest"

import { LandingPage } from "@/components/landing-page"
import { site } from "@/lib/site"

afterEach(cleanup)

describe("LandingPage", () => {
  it("leads with the headline", () => {
    render(<LandingPage />)
    const heading = screen.getByRole("heading", { level: 1 })
    expect(heading.textContent).toBe(site.tagline)
  })

  it("offers the download and source links", () => {
    render(<LandingPage />)
    const downloads = screen.getAllByRole("link", {
      name: /download for macos/i,
    })
    expect(downloads.length).toBeGreaterThanOrEqual(2)
    for (const link of downloads) {
      expect(link.getAttribute("href")).toBe(site.downloadUrl)
    }
    const github = screen.getAllByRole("link", { name: /view on github/i })
    expect(github[0]?.getAttribute("href")).toBe(site.githubUrl)
  })

  it("has the key sections", () => {
    render(<LandingPage />)
    for (const id of ["features", "how-it-works", "privacy", "faq"]) {
      const section = document.getElementById(id)
      expect(section).not.toBeNull()
      expect(
        within(section as HTMLElement).getByRole("heading", { level: 2 })
      ).toBeDefined()
    }
  })

  it("answers the common questions", () => {
    render(<LandingPage />)
    const faq = document.getElementById("faq")
    expect(faq).not.toBeNull()
    expect(
      within(faq as HTMLElement).getByRole("button", {
        name: /api key/i,
      })
    ).toBeDefined()
  })

  it("names the product from the site constant", () => {
    render(<LandingPage />)
    expect(screen.getAllByText(site.name).length).toBeGreaterThan(0)
  })
})
