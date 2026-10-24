import { site } from "@/lib/site"

const facts: { lead: string; body: string }[] = [
  {
    lead: "Stored on your Mac.",
    body: "Your word book, history and review progress live in a local database.",
  },
  {
    lead: "No account.",
    body: "There is nothing to sign up for, and the app sends no analytics.",
  },
  {
    lead: "Your own key.",
    body: "Any OpenAI-compatible API works. Requests go from your Mac straight to that provider.",
  },
  {
    lead: "Or a local model.",
    body: "Point it at Ollama and lookups never leave the Mac.",
  },
  {
    lead: "Works without a key.",
    body: "The offline dictionary and Apple Translation cover lookups from the first launch.",
  },
  {
    lead: "Open source.",
    body: `The code is on GitHub under ${site.license}, so you can check all of this.`,
  },
]

export function Privacy() {
  return (
    <section
      id="privacy"
      aria-labelledby="privacy-title"
      className="px-4 pb-32 md:pb-44"
    >
      <div className="mx-auto max-w-[1000px]">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <h2
            id="privacy-title"
            className="font-display text-[clamp(2rem,4vw,3rem)] leading-[1.08]"
          >
            Where your text goes
          </h2>
          <p className="max-w-[26rem] text-[16px] leading-[26px] text-muted-foreground">
            Nothing passes through a server of ours, because there isn&apos;t
            one.
          </p>
        </div>
        <ul className="mt-10 grid gap-px border-y bg-border sm:grid-cols-2 lg:grid-cols-3">
          {facts.map((fact) => (
            <li
              key={fact.lead}
              className="bg-background px-1 py-6 text-[14px] leading-[22px] text-muted-foreground sm:px-6"
            >
              <span className="font-medium text-foreground">{fact.lead}</span>{" "}
              {fact.body}
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
