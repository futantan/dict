import { AppMark, Keycap } from "@/components/cards"
import { DownloadButton } from "@/components/download"
import { site } from "@/lib/site"

function Closing() {
  return (
    <section
      aria-labelledby="closing-title"
      className="mx-auto max-w-[1100px] px-4 pb-28"
    >
      <div className="shadow-hairline grid items-center gap-10 overflow-hidden rounded-xl bg-[linear-gradient(115deg,#d4e9ff_0%,#e9f1fb_35%,#f6f6f6_75%)] px-6 py-12 sm:px-12 md:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)] md:py-16 dark:bg-[linear-gradient(115deg,#13245a_0%,#121a33_40%,#121621_80%)]">
        <div className="flex flex-col items-start gap-5">
          <AppMark className="size-11" />
          <h2
            id="closing-title"
            className="font-display text-[clamp(1.75rem,3.4vw,2.5rem)] leading-[1.12] text-balance"
          >
            Try it on the next email you get in English
          </h2>
          <p className="text-[14px] leading-[22px] text-muted-foreground">
            Free, {site.license}, for {site.minMacOS} or later.
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <DownloadButton />
            <a
              href={site.githubUrl}
              className="shadow-float inline-flex h-10 items-center rounded-full bg-card px-5 text-[15px] transition-colors hover:bg-muted"
            >
              Source on GitHub
            </a>
          </div>
        </div>
        <div
          aria-hidden="true"
          className="hidden items-center justify-center gap-4 md:flex"
        >
          <Keycap className="h-24 min-w-28 rounded-xl text-[34px]">
            {site.readKey}
          </Keycap>
          <Keycap className="h-24 min-w-28 rotate-3 rounded-xl text-[34px]">
            {site.writeKey}
          </Keycap>
        </div>
      </div>
    </section>
  )
}

const columns = [
  {
    title: "Product",
    links: [
      { label: "Download", href: site.downloadUrl },
      { label: "Features", href: "#features" },
      { label: "Word book", href: "#word-book" },
    ],
  },
  {
    title: "Project",
    links: [
      { label: "GitHub", href: site.githubUrl },
      { label: "Privacy", href: "#privacy" },
      { label: "FAQ", href: "#faq" },
    ],
  },
]

export function SiteFooter() {
  return (
    <footer>
      <Closing />
      <div className="border-t">
        <div className="mx-auto flex max-w-[1100px] flex-col gap-10 px-4 py-14 sm:flex-row sm:justify-between">
          <div className="flex flex-col gap-4">
            <span className="font-display flex items-center gap-2 text-[17px]">
              <AppMark className="size-6" />
              {site.name}
            </span>
            <span className="flex items-center gap-2 text-[13px] text-muted-foreground">
              <span className="size-1.5 rounded-full bg-diff-insert" />
              Open source under {site.license}
            </span>
          </div>
          <div className="flex gap-16 text-[14px]">
            {columns.map((column) => (
              <div key={column.title} className="flex flex-col gap-3">
                <span className="text-[13px] text-muted-foreground">
                  {column.title}
                </span>
                {column.links.map((link) => (
                  <a
                    key={link.label}
                    href={link.href}
                    className="transition-colors hover:text-primary"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            ))}
          </div>
        </div>
      </div>
    </footer>
  )
}
