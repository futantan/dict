import { cn } from "@workspace/ui/lib/utils"
import { useEffect, useState } from "react"

import { AppMark } from "@/components/cards"
import { site } from "@/lib/site"

const links = [
  { href: "#features", label: "Features" },
  { href: "#word-book", label: "Word book" },
  { href: "#privacy", label: "Privacy" },
  { href: "#faq", label: "FAQ" },
]

// Wide and clear over the dark hero; a compact white pill once the page moves.
export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > 24)
    update()
    window.addEventListener("scroll", update, { passive: true })
    return () => window.removeEventListener("scroll", update)
  }, [])

  return (
    <header className="fixed inset-x-0 top-0 z-50 px-4 pt-3">
      <nav
        aria-label="Main"
        className={cn(
          "mx-auto flex h-12 items-center gap-6 rounded-full pr-1.5 pl-3 transition-[max-width,background-color,box-shadow,color] duration-300",
          scrolled
            ? "shadow-float max-w-[640px] bg-card/95 text-foreground backdrop-blur-xl"
            : "max-w-6xl text-white"
        )}
      >
        <a
          href="#top"
          className="font-display flex items-center gap-2 text-[17px]"
        >
          <AppMark className="size-6" />
          {site.name}
        </a>
        <ul className="mx-auto hidden items-center gap-6 text-[14px] md:flex">
          {links.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className={cn(
                  "transition-colors",
                  scrolled
                    ? "text-muted-foreground hover:text-foreground"
                    : "text-white/75 hover:text-white"
                )}
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          href={site.downloadUrl}
          className="shadow-button ml-auto flex h-9 items-center rounded-full bg-primary px-4 text-[14px] font-medium text-primary-foreground transition-colors hover:bg-primary/90 md:ml-0"
        >
          Download
        </a>
      </nav>
    </header>
  )
}
