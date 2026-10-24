import { site } from "@/lib/site"

const questions: { q: string; a: string }[] = [
  {
    q: `Is ${site.name} free?`,
    a: `Yes, and the source is open under ${site.license}. If you use a paid model provider, you pay them directly for what you use.`,
  },
  {
    q: "Do I need an API key?",
    a: "No. The offline dictionary, Apple Translation and the system spell checker work without one. A key, or a local Ollama model, adds the meaning-in-this-sentence line and the rewrites.",
  },
  {
    q: "Which languages does it support?",
    a: "The defaults are for Chinese speakers reading and writing English, and the offline dictionary is English to Simplified Chinese. You can change both languages in Settings.",
  },
  {
    q: "Which Mac do I need?",
    a: `Any Mac running ${site.minMacOS} (Sequoia) or later.`,
  },
  {
    q: "Why does macOS warn me the first time I open it?",
    a: "Early builds are signed but not yet notarized by Apple. Open System Settings › Privacy & Security and choose Open Anyway once. Updates after that install without the warning.",
  },
]

export function Faq() {
  return (
    <section
      id="faq"
      aria-labelledby="faq-title"
      className="px-4 pb-32 md:pb-40"
    >
      <div className="mx-auto grid max-w-[1000px] gap-10 md:grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] md:gap-16">
        <h2
          id="faq-title"
          className="font-display text-[clamp(2.25rem,5vw,4rem)] leading-[1.12]"
        >
          Questions
        </h2>
        <div className="flex flex-col gap-1">
          {questions.map(({ q, a }) => (
            <details
              key={q}
              className="group rounded-xl transition-colors open:bg-tile hover:bg-tile"
            >
              <summary className="flex list-none items-center justify-between gap-4 px-4 py-3.5 text-[15px] font-medium [&::-webkit-details-marker]:hidden">
                {q}
                <svg
                  viewBox="0 0 16 16"
                  aria-hidden="true"
                  className="size-3.5 shrink-0 text-muted-foreground transition-transform group-open:rotate-45"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.6"
                  strokeLinecap="round"
                >
                  <path d="M8 3v10M3 8h10" />
                </svg>
              </summary>
              <p className="px-4 pb-4 text-[14px] leading-[22px] text-muted-foreground">
                {a}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
