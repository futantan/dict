import { cn } from "@workspace/ui/lib/utils"
import type { ReactNode } from "react"

// Hand-built product visuals. They mirror the app's panel design
// (apps/macos/Design/option-a) and are decorative, so screen readers skip them.

export function AppMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      aria-hidden="true"
      className={cn("size-7 shrink-0", className)}
    >
      <rect width="32" height="32" rx="8" className="fill-primary" />
      <rect x="7" y="9" width="18" height="2.6" rx="1.3" fill="#fff" />
      <rect x="7" y="14.7" width="14" height="2.6" rx="1.3" fill="#ffe58f" />
      <rect x="7" y="20.4" width="10" height="2.6" rx="1.3" fill="#fff" />
    </svg>
  )
}

export function Keycap({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <kbd
      className={cn(
        "inline-flex h-7 min-w-7 items-center justify-center rounded-md border border-b-2 bg-card px-1.5 font-sans text-[13px] font-semibold text-foreground shadow-xs",
        className
      )}
    >
      {children}
    </kbd>
  )
}

export function Panel({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "flex w-full flex-col gap-4 rounded-[18px] bg-card px-5 pt-5 pb-4 text-left text-card-foreground shadow-[0_0_0_0.5px_rgb(0_0_0/0.14),0_18px_50px_-12px_rgb(0_0_0/0.28)] dark:shadow-[0_0_0_0.5px_rgb(255_255_255/0.12),0_18px_50px_-12px_rgb(0_0_0/0.7)]",
        className
      )}
    >
      {children}
    </div>
  )
}

function Pill({
  children,
  tone = "brand",
}: {
  children: ReactNode
  tone?: "brand" | "success" | "neutral"
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-[12px] leading-[18px] font-semibold whitespace-nowrap",
        tone === "brand" && "bg-accent text-accent-foreground",
        tone === "success" && "bg-diff-insert-bg text-diff-insert",
        tone === "neutral" && "bg-secondary text-secondary-foreground"
      )}
    >
      {children}
    </span>
  )
}

function IconSlot({ d }: { d: string }) {
  return (
    <span className="flex size-8 items-center justify-center rounded-lg text-muted-foreground">
      <svg
        viewBox="0 0 16 16"
        className="size-[18px]"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d={d} />
      </svg>
    </span>
  )
}

const speaker = "M2.5 6v4h2.5l3.5 3V3L5 6zM11 5.5a3.5 3.5 0 0 1 0 5"
const star =
  "M8 1.8l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z"
const copy =
  "M5.5 5.5h8v8h-8zM10.5 5.5V4A1.5 1.5 0 0 0 9 2.5H4A1.5 1.5 0 0 0 2.5 4v5A1.5 1.5 0 0 0 4 10.5h1.5"

function Sense({ pos, children }: { pos: string; children: ReactNode }) {
  return (
    <>
      <span className="w-11 rounded-md bg-accent text-center text-[12px] leading-[18px] font-semibold text-accent-foreground">
        {pos}
      </span>
      <span>{children}</span>
    </>
  )
}

export type Entry = {
  word: string
  ipa: string
  accent: "US" | "UK"
  frequency: string
  senses: { pos: string; gloss: string }[]
  meaning: string
  sentence: [before: string, after: string]
  seen: string
}

export const tentative: Entry = {
  word: "tentative",
  ipa: "/ˈten.tə.tɪv/",
  accent: "US",
  frequency: "Common",
  senses: [
    { pos: "adj.", gloss: "暂定的，试探性的" },
    { pos: "adj.", gloss: "犹豫的，不确定的" },
  ],
  meaning: "暂定的（日期还没最终确定）",
  sentence: ["We picked a ", " date for the launch."],
  seen: "3rd time",
}

export function LookupCard({
  entry = tentative,
  className,
}: {
  entry?: Entry
  className?: string
}) {
  return (
    <Panel className={className}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex flex-col gap-2">
          <div className="text-[28px] leading-[1.1] font-bold tracking-[-0.4px]">
            {entry.word}
          </div>
          <div className="flex items-center gap-2 text-[13px] text-muted-foreground">
            <span className="rounded bg-secondary px-1 text-[10.5px] font-semibold text-secondary-foreground">
              {entry.accent}
            </span>
            <span>{entry.ipa}</span>
            <Pill tone="success">{entry.frequency}</Pill>
          </div>
        </div>
        <IconSlot d={speaker} />
      </div>
      <div className="grid grid-cols-[44px_1fr] items-baseline gap-x-3 gap-y-2 text-[15px] leading-normal">
        {entry.senses.map((sense) => (
          <Sense key={sense.gloss} pos={sense.pos}>
            {sense.gloss}
          </Sense>
        ))}
      </div>
      <div className="flex flex-col gap-1.5 rounded-xl bg-accent/70 px-3.5 py-3">
        <div className="text-[11.5px] font-semibold text-accent-foreground">
          In this sentence
        </div>
        <div className="text-[15px] font-semibold">{entry.meaning}</div>
        <div className="text-[13px] leading-relaxed text-muted-foreground">
          {entry.sentence[0]}
          <mark className="rounded-[3px] bg-highlight px-0.5 text-highlight-foreground">
            {entry.word}
          </mark>
          {entry.sentence[1]}
        </div>
      </div>
      <div className="flex items-center justify-between gap-2">
        <Pill>{entry.seen}</Pill>
        <div className="flex items-center">
          <IconSlot d={copy} />
          <IconSlot d={star} />
        </div>
      </div>
    </Panel>
  )
}

function Del({ children }: { children: ReactNode }) {
  return <del className="text-diff-delete">{children}</del>
}

function Ins({ children }: { children: ReactNode }) {
  return (
    <ins className="ml-0.5 rounded-[3px] bg-diff-insert-bg px-0.5 text-diff-insert no-underline">
      {children}
    </ins>
  )
}

export function CorrectionCard({ className }: { className?: string }) {
  return (
    <Panel className={className}>
      <p className="text-[16px] leading-[1.7]">
        Thanks for the notes. I <Del>have went</Del>
        <Ins>went</Ins> through them yesterday and <Del>agree</Del>
        <Ins>agree with</Ins> most of <Del>it</Del>
        <Ins>them</Ins>. Can we keep the date tentative until Friday?
      </p>
      <div className="flex items-center justify-between gap-2">
        <Pill>Accepted 3/3</Pill>
        <div className="flex items-center gap-1">
          <IconSlot d={copy} />
          <span className="flex h-8 items-center gap-2 rounded-full bg-primary pr-1.5 pl-3.5 text-[13px] font-semibold text-primary-foreground">
            Replace
            <span className="flex size-[18px] items-center justify-center rounded-[5px] bg-white/20 text-[11px]">
              ↩
            </span>
          </span>
        </div>
      </div>
    </Panel>
  )
}

export function ReviewCard({ className }: { className?: string }) {
  return (
    <Panel className={className}>
      <div className="flex items-center justify-between gap-2 text-[12px] font-semibold text-muted-foreground">
        <span>Review · 7 of 12</span>
        <span>From Mail, Oct 21</span>
      </div>
      <p className="font-display text-[22px] leading-snug">
        We picked a{" "}
        <span className="inline-block w-28 border-b-2 border-brand pl-1 text-brand">
          t
        </span>{" "}
        date for the launch.
      </p>
      <div className="text-[13px] text-muted-foreground">
        暂定的 · adj. · you looked this up 3 times
      </div>
      <div className="grid grid-cols-2 gap-2">
        <span className="flex h-9 items-center justify-center gap-2 rounded-full bg-secondary text-[13px] font-semibold text-secondary-foreground">
          Forgot
          <span className="flex size-5 items-center justify-center rounded-[5px] bg-foreground/10 text-[11px]">
            1
          </span>
        </span>
        <span className="flex h-9 items-center justify-center gap-2 rounded-full bg-primary text-[13px] font-semibold text-primary-foreground">
          Remembered
          <span className="flex size-5 items-center justify-center rounded-[5px] bg-white/20 text-[11px]">
            2
          </span>
        </span>
      </div>
    </Panel>
  )
}

export function MenuBar({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "flex h-7 items-center justify-between bg-background/60 px-3 text-[12px] font-medium text-foreground/80 backdrop-blur-md",
        className
      )}
    >
      <div className="flex items-center gap-4">
        <span className="font-semibold text-foreground">Mail</span>
        <span className="hidden sm:inline">File</span>
        <span className="hidden sm:inline">Edit</span>
        <span className="hidden sm:inline">View</span>
      </div>
      <div className="flex items-center gap-3">
        <span className="flex items-center rounded-[5px] bg-foreground/10 p-0.5">
          <AppMark className="size-4" />
        </span>
        <span className="tabular-nums">Fri 9:41</span>
      </div>
    </div>
  )
}

export function WindowFrame({
  title,
  children,
  className,
}: {
  title: string
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-xl bg-card shadow-[0_0_0_0.5px_rgb(0_0_0/0.16),0_24px_60px_-20px_rgb(0_0_0/0.35)] dark:shadow-[0_0_0_0.5px_rgb(255_255_255/0.12),0_24px_60px_-20px_rgb(0_0_0/0.8)]",
        className
      )}
    >
      <div className="relative flex h-9 items-center border-b bg-muted/60 px-3">
        <div className="flex gap-1.5">
          <span className="size-3 rounded-full bg-[#ff5f57]" />
          <span className="size-3 rounded-full bg-[#febc2e]" />
          <span className="size-3 rounded-full bg-[#28c840]" />
        </div>
        <span className="absolute inset-x-16 truncate text-center text-[12px] font-semibold text-muted-foreground">
          {title}
        </span>
      </div>
      {children}
    </div>
  )
}
