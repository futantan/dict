import type { ReactNode } from "react"

import { Diff, Keycap } from "@/components/cards"
import { site } from "@/lib/site"

// Each card carries a small working piece of the app, drawn for the page.

function MeaningVisual() {
  return (
    <div className="shadow-float w-[min(300px,100%)] rounded-xl bg-card p-4 text-left transition-transform duration-300 group-hover:-translate-y-1">
      <div className="flex items-baseline justify-between">
        <span className="font-display text-[20px]">settle</span>
        <span className="font-[system-ui] text-[12px] text-muted-foreground">
          US /ˈset̬.əl/
        </span>
      </div>
      <ol className="mt-3 flex flex-col gap-1 text-[13px] text-muted-foreground">
        <li>1. 解决，了结（争端）</li>
        <li>2. 定居，安顿下来</li>
        <li className="rounded-sm bg-accent px-1.5 py-0.5 font-medium text-accent-foreground">
          3. 结清，支付（账单）
        </li>
      </ol>
      <p className="mt-3 border-t pt-3 text-[13px] text-muted-foreground">
        Let&apos;s{" "}
        <mark className="rounded-sm bg-highlight px-0.5 text-highlight-foreground">
          settle
        </mark>{" "}
        the bill and head to the station.
      </p>
    </div>
  )
}

function DiffVisual() {
  return (
    <div className="shadow-float w-[min(320px,100%)] rounded-xl bg-card p-4 text-left transition-transform duration-300 group-hover:-translate-y-1">
      <p className="text-[14px] leading-[1.75]">
        <Diff
          parts={[
            "Sorry for the late reply, I ",
            { del: "was", ins: "have been" },
            " busy ",
            { del: "in", ins: "with" },
            " the release.",
          ]}
        />
      </p>
      <div className="mt-3 flex items-center justify-between border-t pt-3">
        <span className="text-[12px] text-muted-foreground">2 changes</span>
        <span className="shadow-button flex h-7 items-center gap-1.5 rounded-full bg-primary px-3 text-[13px] font-medium text-primary-foreground">
          Replace <span aria-hidden="true">↩</span>
        </span>
      </div>
    </div>
  )
}

const apps = ["Mail", "Safari", "Slack", "Notes", "Pages", "Preview", "Chrome"]

function AppsVisual() {
  return (
    <div className="flex max-w-[320px] flex-col items-center gap-4">
      <div className="flex flex-wrap justify-center gap-2">
        {apps.map((app, index) => (
          <span
            key={app}
            className="shadow-float rounded-full bg-card px-3 py-1.5 text-[13px] transition-transform duration-300 group-hover:-translate-y-0.5"
            style={{ transitionDelay: `${index * 30}ms` }}
          >
            {app}
          </span>
        ))}
        <span className="rounded-full border border-dashed border-foreground/20 px-3 py-1.5 text-[13px] text-muted-foreground">
          text in a screenshot
        </span>
      </div>
      <div className="flex items-center gap-2 text-[13px] text-muted-foreground">
        <Keycap>{site.readKey}</Keycap>
        <Keycap>{site.writeKey}</Keycap>
        <span>work the same in each</span>
      </div>
    </div>
  )
}

function ReviewVisual() {
  return (
    <div className="shadow-float w-[min(300px,100%)] rounded-xl bg-card p-4 text-left transition-transform duration-300 group-hover:-translate-y-1">
      <div className="flex justify-between text-[12px] text-muted-foreground">
        <span>Review, 7 of 18</span>
        <span>Mail, Oct 21</span>
      </div>
      <p className="font-display mt-3 text-[18px] leading-snug">
        We picked a{" "}
        <span className="inline-block w-24 border-b-2 border-primary text-primary">
          t
        </span>{" "}
        date for the launch.
      </p>
      <p className="mt-2 text-[12px] text-muted-foreground">
        暂定的 · adj. · looked up 3 times
      </p>
      <div className="mt-4 grid grid-cols-2 gap-2 text-[13px] font-medium">
        <span className="flex h-8 items-center justify-center rounded-full bg-secondary">
          Forgot
        </span>
        <span className="shadow-button flex h-8 items-center justify-center rounded-full bg-primary text-primary-foreground">
          Remembered
        </span>
      </div>
    </div>
  )
}

const cards: { title: string; body: string; visual: ReactNode }[] = [
  {
    title: "The meaning in this sentence",
    body: `On a single word, ${site.readKey} opens the offline English–Chinese dictionary at once, then your model picks the sense the sentence uses. A longer selection gets a translation.`,
    visual: <MeaningVisual />,
  },
  {
    title: "Fixes you can see first",
    body: `${site.writeKey} checks grammar and spelling and can make the wording sound more natural. Write in Chinese and it comes back in English. Your text is replaced only after you press Return.`,
    visual: <DiffVisual />,
  },
  {
    title: "Wherever you can select text",
    body: "It reads the selection through the macOS accessibility API, so it works in most apps. Text inside an image goes through OCR first.",
    visual: <AppsVisual />,
  },
  {
    title: "Review with your own sentences",
    body: "Words come back in the sentence you met them in, spaced out so the ones you forget return sooner.",
    visual: <ReviewVisual />,
  },
]

export function Features() {
  return (
    <section
      id="features"
      aria-labelledby="features-title"
      className="px-4 pt-24 pb-32 md:pt-28 md:pb-40"
    >
      <div className="mx-auto flex max-w-[1000px] flex-col items-center text-center">
        <h2
          id="features-title"
          className="font-display text-[clamp(2.25rem,5vw,4rem)] leading-[1.12] text-balance"
        >
          What the two keys do
        </h2>
        <p className="mt-4 max-w-[30rem] text-[16px] leading-[26px] text-muted-foreground">
          {site.readKey} is for reading and {site.writeKey} is for writing. You
          can change both shortcuts in Settings.
        </p>
        <div className="mt-14 grid w-full gap-4 md:grid-cols-2">
          {cards.map((card) => (
            <article
              key={card.title}
              className="group flex flex-col items-center rounded-xl bg-tile px-6 pt-6 pb-8 text-center"
            >
              <div
                aria-hidden="true"
                className="flex h-[220px] w-full items-center justify-center sm:h-[280px]"
              >
                {card.visual}
              </div>
              <h3 className="text-[16px] font-medium">{card.title}</h3>
              <span className="my-4 h-px w-32 bg-border" />
              <p className="max-w-[24rem] text-[14px] leading-[22px] text-muted-foreground">
                {card.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
