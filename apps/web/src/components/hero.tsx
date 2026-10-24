import { Demo } from "@/components/demo"
import { DownloadButton } from "@/components/download"
import { site } from "@/lib/site"

// The read key sits inside the headline as a glossy key, the way it sits
// under your finger.
function Headline() {
  const [before, after] = site.headline.split(site.readKey)
  return (
    <h1
      id="hero-title"
      className="font-display max-w-[15ch] bg-gradient-to-b from-white to-[#c9cfe6] bg-clip-text text-[clamp(2.75rem,6.4vw,4.625rem)] leading-[1.14] tracking-[-0.015em] text-balance text-transparent"
    >
      {before}
      <span className="mx-[0.12em] inline-flex h-[0.95em] translate-y-[0.1em] items-center rounded-[0.19em] bg-gradient-to-b from-[#4f7bff] to-[#1035d8] px-[0.18em] align-baseline text-[0.62em] text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.35),inset_0_-2px_0_rgb(0_0_0/0.2),0_6px_16px_-4px_rgb(23_71_255/0.6),0_0_0_1px_rgb(5_6_27/0.5)]">
        {site.readKey}
      </span>
      {after}
    </h1>
  )
}

export function Hero() {
  return (
    <section
      id="top"
      aria-labelledby="hero-title"
      className="relative bg-[linear-gradient(180deg,#060a1c_0%,#071034_55%,#0a1a78_100%)] px-4 pt-36 text-white md:pt-44"
    >
      <div className="mx-auto flex max-w-6xl flex-col items-center text-center">
        <p className="glass mb-7 rounded-full px-3 py-1 text-[13px] text-white/80">
          Menu-bar app for {site.minMacOS} and later
        </p>
        <Headline />
        <p className="mt-6 max-w-[36rem] text-[16px] leading-[26px] text-balance text-white/80">
          {site.name} shows what a word means in the sentence you found it in.
          Press {site.writeKey} on your own writing and it shows the fixes
          before it changes anything.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <DownloadButton />
          <a
            href={site.githubUrl}
            className="glass inline-flex h-10 items-center rounded-full px-5 text-[15px] text-white transition-colors hover:bg-white/15"
          >
            Source on GitHub
          </a>
        </div>
      </div>
      <div className="mt-20 md:mt-24">
        <Demo />
      </div>
    </section>
  )
}
