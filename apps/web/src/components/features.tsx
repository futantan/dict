import { cn } from "@workspace/ui/lib/utils"
import type { ReactNode } from "react"

import {
  type Entry,
  CorrectionCard,
  Keycap,
  LookupCard,
  ReviewCard,
} from "@/components/mock-mac"
import { Eyebrow, SectionHeading } from "@/components/section-heading"
import { site } from "@/lib/site"

const settle: Entry = {
  word: "settle",
  ipa: "/ˈset.əl/",
  accent: "UK",
  frequency: "Common",
  senses: [
    { pos: "v.", gloss: "解决，了结（争端）" },
    { pos: "v.", gloss: "定居，安顿下来" },
    { pos: "v.", gloss: "结清，支付（账单）" },
  ],
  meaning: "结清，付（账单）",
  sentence: ["Let's ", " the bill and head to the station."],
  seen: "1st time",
}

type Feature = {
  eyebrow: string
  title: string
  body: ReactNode
  points: string[]
  visual: ReactNode
}

const features: Feature[] = [
  {
    eyebrow: "01 · Read",
    title: "The meaning in this sentence, not ten meanings in a list.",
    body: (
      <>
        Press <Keycap>{site.readKey}</Keycap> on a word and the offline
        dictionary answers instantly. Then your model reads the whole sentence
        and tells you which sense is meant here.
      </>
    ),
    points: [
      "Instant offline dictionary as the base layer",
      "In-context meaning from the AI model you choose",
      "Pronunciation with the accent you prefer",
    ],
    visual: <LookupCard entry={settle} className="max-w-[380px]" />,
  },
  {
    eyebrow: "02 · Write",
    title: "See every change before it touches your text.",
    body: (
      <>
        Press <Keycap>{site.writeKey}</Keycap> on what you wrote. {site.name}{" "}
        corrects it, polishes it, or translates your native language into the
        one you are writing in, and shows the result as a diff first.
      </>
    ),
    points: [
      "Accept or reject each change from the keyboard",
      "Replaces the text in place only after you confirm",
      "Works in any app where you can select text",
    ],
    visual: <CorrectionCard className="max-w-[420px]" />,
  },
  {
    eyebrow: "03 · Remember",
    title: "Your own sentences make the best flashcards.",
    body: (
      <>
        Every word you looked up and every sentence you got corrected is saved
        with the sentence it came from. A few minutes of review a day turns them
        into vocabulary you actually use.
      </>
    ),
    points: [
      "Daily review that adapts to what you forget",
      "Cloze practice built from your own sentences",
      "Export to CSV or Anki whenever you like",
    ],
    visual: <ReviewCard className="max-w-[400px]" />,
  },
]

function Check() {
  return (
    <svg
      viewBox="0 0 16 16"
      className="mt-1 size-4 shrink-0 text-brand"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="m3.5 8.5 3 3 6-7" />
    </svg>
  )
}

function FeatureRow({ feature, flip }: { feature: Feature; flip: boolean }) {
  return (
    <article className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
      <div className={cn("flex flex-col gap-5", flip && "md:order-2")}>
        <Eyebrow>{feature.eyebrow}</Eyebrow>
        <h3 className="font-display text-[clamp(1.85rem,3.6vw,2.6rem)] leading-[1.08] font-medium text-balance">
          {feature.title}
        </h3>
        <p className="text-[17px] leading-relaxed text-pretty text-muted-foreground [&_kbd]:mx-0.5 [&_kbd]:h-6 [&_kbd]:align-[1px]">
          {feature.body}
        </p>
        <ul className="mt-1 flex flex-col gap-2.5 text-[15px]">
          {feature.points.map((point) => (
            <li key={point} className="flex gap-2.5">
              <Check />
              {point}
            </li>
          ))}
        </ul>
      </div>
      <div
        aria-hidden="true"
        className="wallpaper flex min-w-0 items-center justify-center overflow-hidden rounded-[28px] border px-4 py-12 sm:px-10 sm:py-16"
      >
        {feature.visual}
      </div>
    </article>
  )
}

export function Features() {
  return (
    <section
      id="features"
      aria-labelledby="features-title"
      className="px-4 pt-8 pb-20 md:pt-12 md:pb-28"
    >
      <SectionHeading
        id="features-title"
        eyebrow="Two keys, three habits"
        title="Look it up, write it right, keep it."
        lede="One shortcut for the language coming in, one for the language going out. Everything in between becomes yours."
      />
      <div className="mx-auto mt-16 flex max-w-6xl flex-col gap-20 md:mt-24 md:gap-28">
        {features.map((feature, index) => (
          <FeatureRow
            key={feature.eyebrow}
            feature={feature}
            flip={index % 2 === 1}
          />
        ))}
      </div>
    </section>
  )
}
