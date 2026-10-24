import type { ReactNode } from "react"

import { Keycap } from "@/components/mock-mac"
import { SectionHeading } from "@/components/section-heading"
import { site } from "@/lib/site"

function SelectVisual() {
  return (
    <p className="text-[15px] leading-relaxed text-muted-foreground">
      …keep the date{" "}
      <span className="rounded-[3px] bg-highlight px-0.5 text-highlight-foreground">
        tentative
      </span>
      <span className="ml-px inline-block h-4 w-px translate-y-0.5 bg-foreground motion-safe:animate-pulse" />{" "}
      until Friday…
    </p>
  )
}

function KeysVisual() {
  return (
    <div className="flex flex-wrap items-center gap-3 text-[13px] text-muted-foreground">
      <span className="flex items-center gap-2">
        <Keycap>{site.readKey}</Keycap> read
      </span>
      <span className="text-border">/</span>
      <span className="flex items-center gap-2">
        <Keycap>{site.writeKey}</Keycap> write
      </span>
    </div>
  )
}

function ConfirmVisual() {
  return (
    <div className="flex items-center gap-1.5 text-[15px]">
      <span>I</span>
      <del className="text-diff-delete">have went</del>
      <ins className="rounded-[3px] bg-diff-insert-bg px-1 text-diff-insert no-underline">
        went
      </ins>
      <span className="ml-auto flex h-7 items-center gap-1.5 rounded-full bg-primary pr-1 pl-3 text-[12px] font-semibold text-primary-foreground">
        Replace
        <span className="flex size-5 items-center justify-center rounded bg-white/20 text-[10px]">
          ↩
        </span>
      </span>
    </div>
  )
}

const steps: { title: string; body: string; visual: ReactNode }[] = [
  {
    title: "Select text anywhere",
    body: "Mail, Safari, Slack, a PDF, a screenshot. If you can select it, or see it, it works. An optional selection icon appears too, if you prefer clicking.",
    visual: <SelectVisual />,
  },
  {
    title: "Press one of two keys",
    body: "One key reads: look up or translate. The other writes: correct, polish, or translate into the language you are writing in.",
    visual: <KeysVisual />,
  },
  {
    title: "Read it, or confirm it",
    body: "A small panel appears next to your text. Corrections wait for your yes before they replace anything. Esc and you are back where you were.",
    visual: <ConfirmVisual />,
  },
]

export function HowItWorks() {
  return (
    <section
      id="how-it-works"
      aria-labelledby="how-title"
      className="border-y bg-muted/50 px-4 py-20 md:py-28"
    >
      <SectionHeading
        id="how-title"
        eyebrow="How it works"
        title={
          <>
            No app to switch to.
            <br />
            No tab to open.
          </>
        }
      />
      <ol className="mx-auto mt-14 grid max-w-6xl gap-5 md:mt-20 md:grid-cols-3">
        {steps.map((step, index) => (
          <li
            key={step.title}
            className="flex flex-col gap-5 rounded-3xl border bg-card p-6 sm:p-7"
          >
            <span className="font-display text-[56px] leading-none font-light text-brand italic">
              {index + 1}
            </span>
            <h3 className="text-[19px] font-semibold tracking-tight">
              {step.title}
            </h3>
            <p className="text-[15px] leading-relaxed text-muted-foreground">
              {step.body}
            </p>
            <div
              aria-hidden="true"
              className="mt-auto rounded-2xl border bg-background px-4 py-3.5"
            >
              {step.visual}
            </div>
          </li>
        ))}
      </ol>
    </section>
  )
}
