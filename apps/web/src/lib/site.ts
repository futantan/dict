// Everything that names or links the product lives here, so a rename is one edit.
const headline = { lead: "Your second language,", mark: "one keystroke away." }

export const site = {
  name: "Dict",
  headline,
  tagline: `${headline.lead} ${headline.mark}`,
  description:
    "A native macOS menu-bar app for people who live in a second language. Select text anywhere to look it up or fix it, and turn every word you meet into your own review material.",
  downloadUrl: "#",
  githubUrl: "#",
  license: "GPL-3.0",
  minMacOS: "macOS 15",
  readKey: "⌥A",
  writeKey: "⌥F",
} as const
