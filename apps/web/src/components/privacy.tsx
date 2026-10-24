import {
  CpuIcon,
  EyeIcon,
  HardDriveIcon,
  KeyRoundIcon,
  ScanTextIcon,
  Volume2Icon,
  type LucideIcon,
} from "lucide-react"

import { SectionHeading } from "@/components/section-heading"
import { site } from "@/lib/site"

type Item = { icon: LucideIcon; title: string; body: string }

const items: Item[] = [
  {
    icon: HardDriveIcon,
    title: "Stays on your Mac",
    body: "Your words, sentences and review history live in a local database. No account, no sync server, no telemetry.",
  },
  {
    icon: KeyRoundIcon,
    title: "Bring your own model",
    body: "Use your own OpenAI or compatible API key, or run a local model with Ollama. Requests go straight from your Mac to the provider you picked.",
  },
  {
    icon: CpuIcon,
    title: "Works with zero setup",
    body: "No key yet? Apple Translation, the system spell checker and built-in voices cover the basics from the first launch.",
  },
  {
    icon: Volume2Icon,
    title: "Hear it right",
    body: "Pronunciation in the accent you choose, with phonetics on every card.",
  },
  {
    icon: ScanTextIcon,
    title: "Text in images, too",
    body: "Text you can see but not select, like a screenshot or an image, can be read with OCR and looked up the same way.",
  },
  {
    icon: EyeIcon,
    title: "Open to inspect",
    body: `Every line is open source under ${site.license}. Read it, build it, change it.`,
  },
]

export function Privacy() {
  return (
    <section
      id="privacy"
      aria-labelledby="privacy-title"
      className="px-4 py-20 md:py-28"
    >
      <SectionHeading
        id="privacy-title"
        eyebrow="Yours, on your terms"
        title="Private by default. Yours to configure."
        lede="Chinese speakers learning English get sensible defaults. Every language pair, model and voice can be changed."
      />
      <ul className="mx-auto mt-14 grid max-w-6xl gap-px overflow-hidden rounded-3xl border bg-border sm:grid-cols-2 md:mt-20 lg:grid-cols-3">
        {items.map(({ icon: Icon, title, body }) => (
          <li key={title} className="flex flex-col gap-3 bg-card p-7">
            <span className="flex size-10 items-center justify-center rounded-xl bg-accent text-accent-foreground">
              <Icon className="size-5" strokeWidth={1.6} aria-hidden="true" />
            </span>
            <h3 className="mt-2 text-[17px] font-semibold tracking-tight">
              {title}
            </h3>
            <p className="text-[15px] leading-relaxed text-muted-foreground">
              {body}
            </p>
          </li>
        ))}
      </ul>
    </section>
  )
}
