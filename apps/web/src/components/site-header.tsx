import { buttonVariants } from "@workspace/ui/components/button"
import { cn } from "@workspace/ui/lib/utils"

import { AppMark } from "@/components/mock-mac"
import { site } from "@/lib/site"

const links = [
  { href: "#features", label: "Features" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#privacy", label: "Privacy" },
  { href: "#faq", label: "FAQ" },
]

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-50 px-4 pt-3 sm:pt-4">
      <nav
        aria-label="Main"
        className="mx-auto flex h-14 max-w-5xl items-center justify-between gap-4 rounded-full border bg-background/75 py-2 pr-2 pl-4 shadow-[0_8px_30px_-12px_rgb(0_0_0/0.18)] backdrop-blur-xl"
      >
        <a
          href="#top"
          className="flex items-center gap-2.5 text-[17px] font-semibold tracking-tight"
        >
          <AppMark />
          <span>{site.name}</span>
        </a>
        <ul className="hidden items-center gap-1 md:flex">
          {links.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className="rounded-full px-3 py-1.5 text-[14px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>
        <a
          href={site.downloadUrl}
          className={cn(buttonVariants({ size: "default" }), "h-10 px-4")}
        >
          Download
        </a>
      </nav>
    </header>
  )
}
