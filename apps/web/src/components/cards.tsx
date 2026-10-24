import { cn } from "@workspace/ui/lib/utils"
import type { ReactNode } from "react"

// Small pieces of the app's own UI, drawn by hand for the page.

export function AppMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      aria-hidden="true"
      className={cn("size-7 shrink-0", className)}
    >
      <defs>
        <linearGradient id="app-mark" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3d6bff" />
          <stop offset="1" stopColor="#0f35d6" />
        </linearGradient>
      </defs>
      <rect width="32" height="32" rx="8" fill="url(#app-mark)" />
      <rect
        x="0.5"
        y="0.5"
        width="31"
        height="31"
        rx="7.5"
        fill="none"
        stroke="#fff"
        strokeOpacity="0.25"
      />
      <rect x="7" y="9" width="18" height="2.6" rx="1.3" fill="#fff" />
      <rect x="6" y="14.2" width="16" height="3.6" rx="1" fill="#ffd84a" />
      <rect x="7" y="20.4" width="11" height="2.6" rx="1.3" fill="#fff" />
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
        "keycap inline-flex h-6 min-w-6 items-center justify-center rounded-md bg-card px-1.5 font-sans text-[13px] font-medium text-foreground",
        className
      )}
    >
      {children}
    </kbd>
  )
}

export type Entry = {
  word: string
  ipa: string
  pos: string
  senses: string[]
  meaning: string
  sentence: [before: string, after: string]
  note: string
}

export function LookupCard({ entry }: { entry: Entry }) {
  return (
    <div className="flex flex-col gap-3.5 p-4">
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-display text-[24px] leading-none">
          {entry.word}
        </span>
        {/* IPA needs glyphs the text faces lack, so it uses the system face. */}
        <span className="font-[system-ui] text-[13px] text-muted-foreground">
          US {entry.ipa}
        </span>
      </div>
      <ol className="flex flex-col gap-1.5 text-[14px] leading-snug">
        {entry.senses.map((sense, index) => (
          <li key={sense} className="flex gap-2.5">
            <span className="w-14 shrink-0 text-[12px] leading-5 text-muted-foreground">
              {index === 0 ? entry.pos : ""}
            </span>
            <span>{sense}</span>
          </li>
        ))}
      </ol>
      <div className="flex flex-col gap-1 rounded-md bg-accent px-3 py-2.5">
        <span className="text-[12px] font-medium text-accent-foreground">
          In this sentence
        </span>
        <span className="text-[14px] font-medium">{entry.meaning}</span>
        <span className="text-[13px] leading-relaxed text-muted-foreground">
          {entry.sentence[0]}
          <mark className="rounded-sm bg-highlight px-0.5 text-highlight-foreground">
            {entry.word}
          </mark>
          {entry.sentence[1]}
        </span>
      </div>
      <span className="text-[12px] text-muted-foreground">{entry.note}</span>
    </div>
  )
}

export type DiffPart = string | { del: string; ins: string }

export function Diff({ parts }: { parts: DiffPart[] }) {
  return parts.map((part, index) =>
    typeof part === "string" ? (
      part
    ) : (
      <span key={index}>
        <del className="text-diff-delete decoration-1">{part.del}</del>{" "}
        <ins className="rounded-sm bg-diff-insert-bg px-0.5 text-diff-insert no-underline">
          {part.ins}
        </ins>
      </span>
    )
  )
}

export function CorrectionCard({
  parts,
  onReplace,
  onDismiss,
}: {
  parts: DiffPart[]
  onReplace: () => void
  onDismiss: () => void
}) {
  const changes = parts.filter((part) => typeof part !== "string").length
  return (
    <div className="flex flex-col gap-3.5 p-4">
      <p className="text-[14px] leading-[1.75]">
        <Diff parts={parts} />
      </p>
      <div className="flex items-center justify-between gap-2 border-t pt-3">
        <span className="text-[12px] text-muted-foreground">
          {changes === 0 ? "Nothing to fix" : `${changes} changes`}
        </span>
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={onDismiss}
            className="h-7 rounded-full px-3 text-[13px] text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
          >
            Esc
          </button>
          {changes > 0 && (
            <button
              type="button"
              onClick={onReplace}
              className="shadow-button flex h-7 items-center gap-1.5 rounded-full bg-primary px-3 text-[13px] font-medium text-primary-foreground transition-colors hover:bg-primary/90"
            >
              Replace <span aria-hidden="true">↩</span>
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
