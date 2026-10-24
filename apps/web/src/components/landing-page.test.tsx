import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react"
import { afterEach, describe, expect, it } from "vitest"

import { LandingPage } from "@/components/landing-page"
import { site } from "@/lib/site"

afterEach(cleanup)

const card = () => screen.getByRole("status")

describe("LandingPage", () => {
  it("leads with the headline", () => {
    render(<LandingPage />)
    const heading = screen.getByRole("heading", { level: 1 })
    expect(heading.textContent).toBe(site.headline)
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
    const github = screen.getAllByRole("link", { name: /github/i })
    expect(github[0]?.getAttribute("href")).toBe(site.githubUrl)
  })

  it("looks up the selected word when the read key is pressed", () => {
    render(<LandingPage />)
    expect(within(card()).queryByText("暂定的，试探性的")).toBeNull()
    fireEvent.click(screen.getByRole("button", { name: /look up/i }))
    expect(within(card()).getByText("暂定的，试探性的")).toBeDefined()
  })

  it("looks up another word picked in the text, from the keyboard", () => {
    render(<LandingPage />)
    fireEvent.click(screen.getByRole("button", { name: "circle back" }))
    fireEvent.keyDown(window, { code: "KeyA", altKey: true, key: "å" })
    expect(within(card()).getByText(/回头再联系/)).toBeDefined()
    fireEvent.keyDown(window, { key: "Escape" })
    expect(within(card()).queryByText(/回头再联系/)).toBeNull()
  })

  it("shows the correction as a diff and replaces the draft on confirm", () => {
    render(<LandingPage />)
    fireEvent.click(screen.getByRole("button", { name: /check my reply/i }))
    const diff = card()
    expect(diff.querySelector("del")?.textContent).toBe("have went")
    expect(diff.querySelector("ins")?.textContent).toBe("went")
    fireEvent.click(within(diff).getByRole("button", { name: /replace/i }))
    expect(screen.getByText(/I went through the notes/)).toBeDefined()
  })

  it("has the key sections", () => {
    render(<LandingPage />)
    for (const id of ["features", "word-book", "privacy", "faq"]) {
      const section = document.getElementById(id)
      expect(section).not.toBeNull()
      expect(
        within(section as HTMLElement).getByRole("heading", { level: 2 })
      ).toBeDefined()
    }
  })

  it("answers the common questions", () => {
    render(<LandingPage />)
    const faq = document.getElementById("faq") as HTMLElement
    expect(within(faq).getByText(/do i need an api key/i)).toBeDefined()
  })

  it("names the product from the site constant", () => {
    render(<LandingPage />)
    expect(screen.getAllByText(site.name).length).toBeGreaterThan(0)
  })
})
