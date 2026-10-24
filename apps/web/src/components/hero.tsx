import { CtaButtons, CtaFootnote } from "@/components/cta-buttons"
import { Keycap, LookupCard, MenuBar, WindowFrame } from "@/components/mock-mac"
import { site } from "@/lib/site"

function MailMock() {
  return (
    <WindowFrame title="Re: Launch date" className="w-full md:w-[66%]">
      <div className="flex flex-col gap-3 px-5 pt-5 pb-14 text-[14px] leading-relaxed sm:px-7 sm:text-[15px] md:min-h-[340px] md:pb-5">
        <div className="flex flex-col gap-1 border-b pb-3 text-[13px] text-muted-foreground">
          <span>
            <span className="text-foreground/70">From:</span> Priya Raman
          </span>
          <span>
            <span className="text-foreground/70">Subject:</span> Re: Launch date
          </span>
        </div>
        <p>Hi Wei,</p>
        <p>
          Thanks for pulling this together. We picked a{" "}
          <span className="relative">
            <span className="rounded-[3px] bg-highlight px-0.5 text-highlight-foreground">
              tentative
            </span>
            <span className="absolute -top-9 left-1/2 hidden -translate-x-1/2 items-center gap-1 rounded-lg border bg-card px-1.5 py-1 shadow-md sm:flex">
              <Keycap className="h-6 min-w-6 text-[12px]">
                {site.readKey}
              </Keycap>
            </span>
          </span>{" "}
          date for the launch, but legal still needs to sign off on the wording.
        </p>
        <p className="text-muted-foreground">
          I&apos;ll circle back once I hear from them. Until then, let&apos;s
          keep it between us.
        </p>
        <p className="hidden text-muted-foreground md:block">
          Best,
          <br />
          Priya
        </p>
      </div>
    </WindowFrame>
  )
}

function HeroStage() {
  return (
    <div
      aria-hidden="true"
      className="wallpaper relative mx-auto w-full max-w-6xl overflow-hidden rounded-[28px] border shadow-[0_40px_120px_-40px_rgb(91_63_214/0.45)]"
    >
      <MenuBar />
      <div className="relative px-4 pt-8 pb-6 sm:px-8 md:px-12 md:pt-12 md:pb-20">
        <MailMock />
        <div className="relative z-10 -mt-10 ml-auto w-[92%] max-w-[360px] sm:mr-auto md:absolute md:top-24 md:right-10 md:mt-0 lg:right-16">
          <LookupCard />
        </div>
      </div>
    </div>
  )
}

export function Hero() {
  return (
    <section
      id="top"
      aria-labelledby="hero-title"
      className="relative px-4 pt-14 pb-20 sm:pt-20 md:pb-28"
    >
      <div className="mx-auto flex max-w-3xl flex-col items-center text-center motion-safe:animate-in motion-safe:duration-700 motion-safe:fade-in motion-safe:slide-in-from-bottom-3">
        <a
          href="#privacy"
          className="mb-7 inline-flex items-center gap-2 rounded-full border bg-card/70 py-1 pr-3 pl-1 text-[13px] text-muted-foreground backdrop-blur transition-colors hover:text-foreground"
        >
          <span className="rounded-full bg-accent px-2 py-0.5 text-[12px] font-semibold text-accent-foreground">
            Open source
          </span>
          <span className="whitespace-nowrap">
            Native for {site.minMacOS}+
            <span className="hidden sm:inline">, private by default</span>
          </span>
        </a>
        <h1
          id="hero-title"
          className="font-display text-[clamp(2.75rem,8vw,5.75rem)] leading-[0.98] font-medium text-balance"
        >
          {site.headline.lead}{" "}
          <em className="marker marker-draw text-highlight-foreground not-italic dark:text-foreground">
            {site.headline.mark}
          </em>
        </h1>
        <p className="mt-7 max-w-xl text-[18px] leading-relaxed text-pretty text-muted-foreground">
          {site.name} lives in your menu bar. Select text in any app, press{" "}
          <Keycap className="mx-0.5 h-6 align-[1px]">{site.readKey}</Keycap> to
          understand it or{" "}
          <Keycap className="mx-0.5 h-6 align-[1px]">{site.writeKey}</Keycap> to
          fix it, and every word you meet becomes yours to keep.
        </p>
        <CtaButtons className="mt-9 w-full justify-center sm:w-auto" />
        <CtaFootnote className="mt-4" />
      </div>
      <div className="mt-16 motion-safe:animate-in motion-safe:delay-200 motion-safe:duration-1000 motion-safe:fill-mode-both motion-safe:fade-in motion-safe:slide-in-from-bottom-6 md:mt-20">
        <HeroStage />
      </div>
    </section>
  )
}
