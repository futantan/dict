import { cn } from "@workspace/ui/lib/utils"
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react"

import {
  type DiffPart,
  type Entry,
  CorrectionCard,
  LookupCard,
} from "@/components/cards"
import { site } from "@/lib/site"

// The hero demo: an email to read and a reply to fix, driven by the same two
// keys as the app. The panel opens under the selection, like the real one.

const entries = {
  tentative: {
    word: "tentative",
    ipa: "/ˈten.tə.tɪv/",
    pos: "adj.",
    senses: ["暂定的，试探性的", "犹豫的，不确定的"],
    meaning: "暂定的：日期还没最终定下来",
    sentence: ["We picked a ", " date for the launch."],
    note: "Third lookup · already in your word book",
  },
  "sign off": {
    word: "sign off",
    ipa: "/ˌsaɪn ˈɔːf/",
    pos: "phr. v.",
    senses: ["签字批准，正式同意", "（信件、节目）结束"],
    meaning: "签字批准：法务要正式认可措辞",
    sentence: ["Legal still has to ", " on the wording."],
    note: "First lookup · saved to your word book",
  },
  "circle back": {
    word: "circle back",
    ipa: "/ˌsɝː.kəl ˈbæk/",
    pos: "phr. v.",
    senses: ["回头再联系，稍后再讨论", "绕回原处"],
    meaning: "等有了消息再来跟进",
    sentence: ["I'll ", " once I hear from them."],
    note: "First lookup · saved to your word book",
  },
} satisfies Record<string, Entry>

type Word = keyof typeof entries
type Panel =
  | { kind: "closed" }
  | { kind: "lookup"; word: Word }
  | { kind: "fix" }
type Key = "read" | "write" | "close"

const draft: DiffPart[] = [
  "Thanks Priya. I ",
  { del: "have went", ins: "went" },
  " through the notes and ",
  { del: "agree", ins: "agree with" },
  " most of ",
  { del: "it", ins: "them" },
  ". ",
  { del: "Lets", ins: "Let's" },
  " keep the date as it is until Friday.",
]
const fixed = draft
  .map((part) => (typeof part === "string" ? part : part.ins))
  .join("")
const original = draft
  .map((part) => (typeof part === "string" ? part : part.del))
  .join("")

const closed: Panel = { kind: "closed" }

function prefersReducedMotion() {
  return (
    window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false
  )
}

export function Demo() {
  const [selected, setSelected] = useState<Word>("tentative")
  const [panel, setPanel] = useState<Panel>(closed)
  const [replied, setReplied] = useState(false)
  const [pressed, setPressed] = useState<Key | null>(null)
  const [last, setLast] = useState<Key>("read")
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const touched = useRef(false)
  const stageRef = useRef<HTMLDivElement>(null)
  const cardRef = useRef<HTMLDivElement>(null)
  const anchors = useRef<Partial<Record<Word | "reply", HTMLElement | null>>>(
    {}
  )

  const flash = useCallback((key: Key) => {
    setPressed(key)
    setLast(key)
    window.setTimeout(() => setPressed(null), 160)
  }, [])

  const read = useCallback(() => {
    touched.current = true
    flash("read")
    setPanel({ kind: "lookup", word: selected })
  }, [flash, selected])

  const write = useCallback(() => {
    touched.current = true
    flash("write")
    setPanel({ kind: "fix" })
  }, [flash])

  const select = (word: Word) => {
    touched.current = true
    setSelected(word)
    setPanel(closed)
  }

  const close = () => {
    touched.current = true
    flash("close")
    setPanel(closed)
  }

  const replace = () => {
    setReplied(true)
    setPanel(closed)
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const plainAlt = event.altKey && !event.metaKey && !event.ctrlKey
      if (plainAlt && event.code === "KeyA") {
        event.preventDefault()
        read()
      } else if (plainAlt && event.code === "KeyF") {
        event.preventDefault()
        write()
      } else if (event.key === "Escape") {
        flash("close")
        setPanel(closed)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [flash, read, write])

  // Play the first lookup once the demo is in view, unless the visitor got
  // there first or asked for less motion.
  useEffect(() => {
    const stage = stageRef.current
    if (!stage || !("IntersectionObserver" in window) || prefersReducedMotion())
      return
    let timer = 0
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry?.isIntersecting) return
        observer.disconnect()
        timer = window.setTimeout(() => {
          if (touched.current) return
          flash("read")
          setPanel({ kind: "lookup", word: "tentative" })
        }, 900)
      },
      { threshold: 0.6 }
    )
    observer.observe(stage)
    return () => {
      observer.disconnect()
      window.clearTimeout(timer)
    }
  }, [flash])

  // Open the panel under its anchor, or above it when there is no room below.
  useLayoutEffect(() => {
    if (panel.kind === "closed") return
    const place = () => {
      const stage = stageRef.current
      const card = cardRef.current
      const anchor =
        anchors.current[panel.kind === "lookup" ? panel.word : "reply"]
      if (!stage || !card || !anchor) return
      const s = stage.getBoundingClientRect()
      const a = anchor.getBoundingClientRect()
      const left = Math.max(
        0,
        Math.min(a.left - s.left, s.width - card.offsetWidth)
      )
      const below = a.bottom - s.top + 8
      const above = a.top - s.top - card.offsetHeight - 8
      const fits = below + card.offsetHeight <= s.height
      setPosition({ top: fits || above < 0 ? below : above, left })
    }
    place()
    window.addEventListener("resize", place)
    return () => window.removeEventListener("resize", place)
  }, [panel])

  const wordButton = (word: Word) => (
    <button
      type="button"
      ref={(node) => {
        anchors.current[word] = node
      }}
      aria-pressed={selected === word}
      onClick={() => select(word)}
      className={cn(
        "rounded-sm underline decoration-foreground/35 decoration-dotted decoration-1 underline-offset-[5px] transition-colors hover:bg-accent hover:decoration-foreground",
        selected === word &&
          panel.kind !== "fix" &&
          "bg-highlight text-highlight-foreground no-underline hover:bg-highlight"
      )}
    >
      {word}
    </button>
  )

  const press = (key: Key) =>
    key === "read" ? read() : key === "write" ? write() : close()

  const steps: { key: Key; label: string; title: string; body: string }[] = [
    {
      key: "read",
      label: site.readKey,
      title: "Look up a word",
      body: "Click a dotted word in the email first.",
    },
    {
      key: "write",
      label: site.writeKey,
      title: "Check my reply",
      body: "The fixes show as a diff on your draft.",
    },
    {
      key: "close",
      label: "Esc",
      title: "Close the panel",
      body: "Your text stays as it was.",
    },
  ]

  return (
    <div className="flex flex-col gap-12 md:gap-14">
      <div className="mx-auto w-full max-w-[1000px]">
        <div className="grid grid-cols-3 md:divide-x md:divide-white/10">
          {steps.map((step) => (
            <button
              key={step.key}
              type="button"
              onClick={() => press(step.key)}
              className={cn(
                "group flex flex-col items-center gap-2 px-2 pb-5 text-center transition-colors md:gap-3 md:px-8",
                last === step.key
                  ? "text-white"
                  : "text-white/55 hover:text-white/85"
              )}
            >
              <span
                className={cn(
                  "glass flex h-9 min-w-12 items-center justify-center rounded-full px-3 text-[14px] font-medium transition-transform",
                  pressed === step.key && "translate-y-px bg-white/20",
                  last === step.key && "bg-white/15"
                )}
              >
                {step.label}
              </span>
              <span className="text-[14px] font-medium md:text-[16px]">
                {step.title}
              </span>
              <span className="hidden max-w-[16rem] text-[14px] leading-[22px] text-white/55 md:block">
                {step.body}
              </span>
            </button>
          ))}
        </div>
        <div aria-hidden="true" className="grid h-px grid-cols-3 bg-white/12">
          {steps.map((step) => (
            <span
              key={step.key}
              className={cn(
                "h-px transition-colors duration-300",
                last === step.key &&
                  "bg-white shadow-[0_0_12px_rgb(255_255_255/0.8)]"
              )}
            />
          ))}
        </div>
      </div>

      <div className="relative mx-auto w-full max-w-[1040px]">
        <Annotation />
        <div className="shadow-panel overflow-hidden rounded-xl bg-white/6 p-1.5 backdrop-blur-sm sm:p-2">
          <div
            ref={stageRef}
            className="relative flex min-h-[460px] flex-col rounded-[10px] bg-card text-card-foreground sm:min-h-[540px]"
          >
            <div className="flex h-10 items-center gap-2 border-b px-4">
              <span className="size-3 rounded-full bg-[#ff5f57]" />
              <span className="size-3 rounded-full bg-[#febc2e]" />
              <span className="size-3 rounded-full bg-[#28c840]" />
              <span className="ml-3 truncate text-[13px] font-medium text-muted-foreground">
                Re: Launch date
              </span>
            </div>
            <div className="grid flex-1 lg:grid-cols-[264px_minmax(0,1fr)]">
              <Inbox />
              <div className="flex flex-col gap-5 px-5 py-5 sm:px-10 sm:py-7">
                <dl className="grid grid-cols-[3.5rem_1fr] gap-y-0.5 text-[13px]">
                  <dt className="text-muted-foreground">From</dt>
                  <dd>Priya Raman</dd>
                  <dt className="text-muted-foreground">To</dt>
                  <dd>Wei Zhang</dd>
                  <dt className="text-muted-foreground">Date</dt>
                  <dd>Tue 21 Oct, 09:14</dd>
                </dl>
                <div className="flex max-w-[60ch] flex-col gap-3 text-[16px] leading-[1.7]">
                  <p>Hi Wei,</p>
                  <p>
                    Thanks for pulling this together. We picked a{" "}
                    {wordButton("tentative")} date for the launch, but legal
                    still has to {wordButton("sign off")} on the wording.
                    I&apos;ll {wordButton("circle back")} once I hear from them.
                  </p>
                  <p>Priya</p>
                </div>
                <div className="flex flex-col gap-2 border-t pt-4">
                  <span className="text-[13px] text-muted-foreground">
                    Your draft reply
                  </span>
                  <p className="max-w-[60ch] text-[16px] leading-[1.7]">
                    <span
                      ref={(node) => {
                        anchors.current.reply = node
                      }}
                      className={cn(
                        panel.kind === "fix" &&
                          "bg-highlight text-highlight-foreground"
                      )}
                    >
                      {replied ? fixed : original}
                    </span>
                  </p>
                </div>
              </div>
            </div>
            <output aria-live="polite" className="block">
              {panel.kind !== "closed" && (
                <div
                  key={panel.kind === "lookup" ? panel.word : "fix"}
                  ref={cardRef}
                  style={position}
                  className={cn(
                    "shadow-float absolute z-10 origin-top-left rounded-xl bg-popover text-popover-foreground motion-safe:animate-[panel-in_160ms_ease-out]",
                    panel.kind === "lookup"
                      ? "w-[min(330px,100%)]"
                      : "w-[min(440px,100%)]"
                  )}
                >
                  {panel.kind === "lookup" ? (
                    <LookupCard entry={entries[panel.word]} />
                  ) : (
                    <CorrectionCard
                      parts={replied ? [fixed] : draft}
                      onReplace={replace}
                      onDismiss={close}
                    />
                  )}
                </div>
              )}
            </output>
          </div>
        </div>
      </div>
    </div>
  )
}

const inbox = [
  {
    from: "Priya Raman",
    subject: "Re: Launch date",
    time: "09:14",
    preview: "Thanks for pulling this together. We picked a…",
  },
  {
    from: "Tom Becker",
    subject: "Invoice 2291",
    time: "08:52",
    preview: "Attached is the invoice for September. Payment is due…",
  },
  {
    from: "Lena Ortiz",
    subject: "Offsite agenda",
    time: "Yesterday",
    preview: "Could you settle the bill with the venue before…",
  },
  {
    from: "Marcus Hale",
    subject: "Quick question",
    time: "Mon",
    preview: "Do you have the bandwidth to review the draft…",
  },
  {
    from: "Ana Silva",
    subject: "Notes from Thursday",
    time: "Mon",
    preview: "One caveat on the numbers: they exclude refunds…",
  },
]

function Inbox() {
  return (
    <ul aria-hidden="true" className="hidden border-r bg-muted p-2 lg:block">
      {inbox.map((mail, index) => (
        <li
          key={mail.subject}
          className={cn(
            "flex flex-col gap-0.5 rounded-md px-3 py-2.5 text-[12px]",
            index === 0 && "shadow-hairline bg-card"
          )}
        >
          <span className="flex justify-between gap-2">
            <span className="text-[13px] font-medium">{mail.from}</span>
            <span className="text-muted-foreground">{mail.time}</span>
          </span>
          <span>{mail.subject}</span>
          <span className="truncate text-muted-foreground">{mail.preview}</span>
        </li>
      ))}
    </ul>
  )
}

// Drawn once by hand: a note in the margin with an arrow into the email.
function Annotation() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute top-40 -right-40 hidden w-36 text-white/80 select-none xl:block"
    >
      <p className="-rotate-6 font-hand text-[20px] leading-tight">
        it&apos;s live, click a dotted word
      </p>
      <svg
        viewBox="0 0 140 70"
        className="mt-1 -ml-6 h-[60px] w-[120px] -scale-x-100"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M6 6c6 26 30 44 66 46 18 1 36-3 56-10" />
        <path d="M116 34c5 2 9 5 12 8-5 2-10 4-14 7" />
      </svg>
    </div>
  )
}
