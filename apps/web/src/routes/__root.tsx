import { HeadContent, Scripts, createRootRoute } from "@tanstack/react-router"
import type { ReactNode } from "react"

import { site } from "@/lib/site"
import appCss from "@/styles.css?url"

// Runs before paint so the page never flashes the wrong theme, and follows
// the system setting when it changes.
const themeScript = `(() => {
  const media = window.matchMedia("(prefers-color-scheme: dark)")
  const apply = () => document.documentElement.classList.toggle("dark", media.matches)
  apply()
  media.addEventListener("change", apply)
})()`

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { name: "color-scheme", content: "light dark" },
      {
        name: "theme-color",
        content: "#fbfbfd",
        media: "(prefers-color-scheme: light)",
      },
      {
        name: "theme-color",
        content: "#131315",
        media: "(prefers-color-scheme: dark)",
      },
      { title: site.name },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", href: "/favicon.svg", type: "image/svg+xml" },
    ],
  }),
  notFoundComponent: () => (
    <main className="mx-auto flex min-h-svh max-w-xl flex-col items-start justify-center gap-3 p-6">
      <h1 className="font-display text-5xl">Not found</h1>
      <p className="text-muted-foreground">
        The requested page could not be found.
      </p>
      <a className="text-brand underline underline-offset-4" href="/">
        Back to {site.name}
      </a>
    </main>
  ),
  shellComponent: RootDocument,
})

function RootDocument({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
