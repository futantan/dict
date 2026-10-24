import { CtaButtons, CtaFootnote } from "@/components/cta-buttons"
import { AppMark } from "@/components/mock-mac"
import { site } from "@/lib/site"

export function ClosingCta() {
  return (
    <section
      aria-labelledby="closing-title"
      className="px-4 pt-8 pb-20 md:pb-28"
    >
      <div className="wallpaper relative mx-auto flex max-w-6xl flex-col items-center overflow-hidden rounded-[32px] border px-6 py-20 text-center md:py-28">
        <AppMark className="size-14 rounded-[14px] shadow-[0_12px_30px_-8px] shadow-primary/50" />
        <h2
          id="closing-title"
          className="font-display mt-8 max-w-3xl text-[clamp(2.3rem,6vw,4.4rem)] leading-[1.02] font-medium text-balance"
        >
          Start keeping the words <span className="marker">you meet.</span>
        </h2>
        <p className="mt-5 max-w-lg text-[17px] leading-relaxed text-pretty text-muted-foreground">
          Install {site.name}, pick your two shortcuts, and read the next email
          in your second language with a little more confidence.
        </p>
        <CtaButtons className="mt-9 w-full justify-center sm:w-auto" />
        <CtaFootnote className="mt-4" />
      </div>
    </section>
  )
}

export function SiteFooter() {
  return (
    <footer className="border-t px-4 py-10">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 text-[14px] text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2.5">
          <AppMark className="size-6" />
          <span className="font-semibold text-foreground">{site.name}</span>
          <span className="hidden sm:inline">·</span>
          <span className="hidden sm:inline">
            A second-language companion for macOS
          </span>
        </div>
        <nav aria-label="Footer">
          <ul className="flex flex-wrap gap-x-6 gap-y-2">
            <li>
              <a className="hover:text-foreground" href={site.githubUrl}>
                GitHub
              </a>
            </li>
            <li>
              <a className="hover:text-foreground" href="#faq">
                FAQ
              </a>
            </li>
            <li>
              <a className="hover:text-foreground" href="#privacy">
                Privacy
              </a>
            </li>
            <li>Open source under {site.license}</li>
          </ul>
        </nav>
      </div>
    </footer>
  )
}
