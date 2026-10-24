import { cn } from "@workspace/ui/lib/utils"

type Row = {
  word: string
  meaning: string
  sentence: [before: string, after: string]
  app: string
  date: string
  count: number
  next: string
}

const rows: Row[] = [
  {
    word: "tentative",
    meaning: "暂定的",
    sentence: ["We picked a ", " date for the launch."],
    app: "Mail",
    date: "Oct 21",
    count: 3,
    next: "Today",
  },
  {
    word: "circle back",
    meaning: "稍后再跟进",
    sentence: ["I'll ", " once I hear from them."],
    app: "Mail",
    date: "Oct 21",
    count: 1,
    next: "Tomorrow",
  },
  {
    word: "caveat",
    meaning: "附加说明，限制条件",
    sentence: ["One ", ": the numbers exclude refunds."],
    app: "Slack",
    date: "Oct 19",
    count: 2,
    next: "Today",
  },
  {
    word: "leverage",
    meaning: "利用，借助",
    sentence: ["We can ", " the existing billing code."],
    app: "Slack",
    date: "Oct 17",
    count: 4,
    next: "Today",
  },
  {
    word: "amortize",
    meaning: "分期摊销",
    sentence: ["We ", " the license over three years."],
    app: "Preview",
    date: "Oct 15",
    count: 1,
    next: "Oct 26",
  },
  {
    word: "nuance",
    meaning: "细微差别",
    sentence: ["Most of the ", " gets lost in the summary."],
    app: "Safari",
    date: "Oct 12",
    count: 2,
    next: "Oct 28",
  },
  {
    word: "hold off",
    meaning: "暂缓，推迟",
    sentence: ["Let's ", " on the announcement."],
    app: "Mail",
    date: "Oct 9",
    count: 2,
    next: "Oct 30",
  },
  {
    word: "scrutiny",
    meaning: "仔细审查",
    sentence: ["The proposal didn't survive ", "."],
    app: "Safari",
    date: "Oct 3",
    count: 1,
    next: "Nov 6",
  },
  {
    word: "bandwidth",
    meaning: "余力，精力",
    sentence: ["I don't have the ", " this week."],
    app: "Slack",
    date: "Sep 30",
    count: 5,
    next: "Nov 14",
  },
  {
    word: "preempt",
    meaning: "预先阻止，抢先",
    sentence: ["We wanted to ", " the obvious questions."],
    app: "Mail",
    date: "Sep 26",
    count: 1,
    next: "Nov 21",
  },
]

const lists = [
  { name: "All words", count: 214 },
  { name: "Due today", count: 18 },
  { name: "Corrections", count: 61 },
  { name: "Learned", count: 93 },
]

function WordBookPanel() {
  return (
    <div
      aria-hidden="true"
      className="shadow-panel overflow-hidden rounded-xl bg-white/6 p-1.5 backdrop-blur-sm sm:p-2"
    >
      <div className="overflow-hidden rounded-[10px] bg-card text-left text-card-foreground">
        <div className="flex h-10 items-center gap-2 border-b px-4">
          <span className="size-3 rounded-full bg-[#ff5f57]" />
          <span className="size-3 rounded-full bg-[#febc2e]" />
          <span className="size-3 rounded-full bg-[#28c840]" />
          <span className="ml-3 text-[13px] font-medium text-muted-foreground">
            Word book
          </span>
          <span className="ml-auto hidden h-6 w-48 items-center rounded-md bg-secondary px-2 text-[12px] text-muted-foreground sm:flex">
            Search 214 words
          </span>
        </div>
        <div className="grid md:grid-cols-[188px_minmax(0,1fr)]">
          <div className="hidden flex-col gap-4 border-r bg-muted p-3 md:flex">
            <ul className="flex flex-col gap-0.5 text-[13px]">
              {lists.map((list, index) => (
                <li
                  key={list.name}
                  className={cn(
                    "flex items-center justify-between rounded-md px-2.5 py-1.5",
                    index === 0 && "shadow-hairline bg-card font-medium"
                  )}
                >
                  {list.name}
                  <span className="text-muted-foreground tabular-nums">
                    {list.count}
                  </span>
                </li>
              ))}
            </ul>
            <div className="shadow-hairline mt-auto flex flex-col gap-2 rounded-md bg-card p-3 text-[12px]">
              <span className="text-muted-foreground">Reviewed this week</span>
              <div className="flex h-10 items-end gap-1">
                {[5, 8, 3, 9, 6, 10, 4].map((h, index) => (
                  <span
                    key={index}
                    style={{ height: `${h * 10}%` }}
                    className={cn(
                      "flex-1 rounded-sm",
                      index === 5 ? "bg-primary" : "bg-primary/25"
                    )}
                  />
                ))}
              </div>
              <span className="font-medium">63 cards, 9 min a day</span>
            </div>
          </div>
          <table className="w-full text-left text-[13px]">
            <thead className="text-muted-foreground">
              <tr className="border-b">
                <th className="py-2 pr-3 pl-4 font-normal">Word</th>
                <th className="hidden py-2 pr-3 font-normal sm:table-cell">
                  Where you met it
                </th>
                <th className="hidden py-2 pr-3 text-right font-normal lg:table-cell">
                  Looked up
                </th>
                <th className="py-2 pr-4 text-right font-normal">Review</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr
                  key={row.word}
                  className="border-b transition-colors last:border-b-0 hover:bg-muted"
                >
                  <td className="py-2.5 pr-3 pl-4 align-top">
                    <div className="flex flex-wrap items-baseline gap-x-2">
                      <span className="font-medium">{row.word}</span>
                      <span className="text-muted-foreground">
                        {row.meaning}
                      </span>
                    </div>
                    <div className="mt-0.5 text-muted-foreground">
                      {row.sentence[0]}
                      <mark className="rounded-sm bg-highlight/50 px-0.5 text-highlight-foreground dark:bg-highlight/20 dark:text-foreground">
                        {row.word}
                      </mark>
                      {row.sentence[1]}
                    </div>
                  </td>
                  <td className="hidden py-2.5 pr-3 align-top whitespace-nowrap text-muted-foreground sm:table-cell">
                    {row.app}, {row.date}
                  </td>
                  <td className="hidden py-2.5 pr-3 text-right align-top text-muted-foreground tabular-nums lg:table-cell">
                    {row.count}×
                  </td>
                  <td className="py-2.5 pr-4 text-right align-top whitespace-nowrap tabular-nums">
                    {row.next === "Today" ? (
                      <span className="rounded-full bg-accent px-2 py-0.5 font-medium text-accent-foreground">
                        Today
                      </span>
                    ) : (
                      <span className="text-muted-foreground">{row.next}</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

function Note({
  children,
  className,
  arrow,
}: {
  children: string
  className: string
  arrow: "down-right" | "down-left"
}) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        "pointer-events-none absolute hidden w-40 text-white/85 select-none xl:block",
        className
      )}
    >
      <p className="font-hand text-[20px] leading-tight">{children}</p>
      <svg
        viewBox="0 0 80 60"
        className={cn(
          "mt-1 h-[52px] w-[70px]",
          arrow === "down-left" ? "-scale-x-100" : "ml-14"
        )}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M6 4c4 22 20 40 62 48" />
        <path d="M56 42c5 4 9 7 12 10-5 1-10 3-15 5" />
      </svg>
    </div>
  )
}

export function WordBook() {
  return (
    <section
      id="word-book"
      aria-labelledby="word-book-title"
      className="bg-(image:--band) px-4 pt-40 pb-44 text-white md:pt-56 md:pb-64"
    >
      <div className="mx-auto flex max-w-6xl flex-col items-center text-center">
        <h2
          id="word-book-title"
          className="font-display max-w-[20ch] text-[clamp(2rem,4vw,3rem)] leading-[1.08] text-balance"
        >
          Every word you look up is kept with its sentence
        </h2>
        <p className="mt-5 max-w-[36rem] text-[16px] leading-[26px] text-white/80">
          The main window lists what each word meant where you met it. Review
          takes a few minutes a day, using your own sentences with the word
          blanked out, and exports to CSV or Anki.
        </p>
      </div>
      <div className="relative mx-auto mt-14 max-w-[1040px] md:mt-16">
        <Note className="top-4 -left-44" arrow="down-right">
          fixes you accepted are kept too
        </Note>
        <Note className="top-8 -right-44" arrow="down-left">
          18 words due today
        </Note>
        <WordBookPanel />
        <p className="mt-4 text-center text-[13px] text-white dark:text-white/60">
          A month of use, made up for this page. Yours starts empty.
        </p>
      </div>
    </section>
  )
}
