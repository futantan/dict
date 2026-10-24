import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@workspace/ui/components/accordion"

import { SectionHeading } from "@/components/section-heading"
import { site } from "@/lib/site"

const questions: { q: string; a: string }[] = [
  {
    q: `Is ${site.name} free?`,
    a: `Yes. ${site.name} is free and open source under ${site.license}. If you use a paid model provider, you pay that provider directly for what you use.`,
  },
  {
    q: "Do I need an API key?",
    a: "No. Without a key, the offline dictionary, Apple Translation, the system spell checker and system voices work out of the box. Add an OpenAI or compatible key, or point it at a local Ollama model, to get in-context meanings and polished rewrites.",
  },
  {
    q: "Where is my data stored?",
    a: `Only on your Mac. Your history, saved words and review progress are kept in a local database. ${site.name} has no account system and sends no analytics. Text goes to a model provider only when you ask for a lookup or rewrite, and only to the provider you configured.`,
  },
  {
    q: "Which languages does it support?",
    a: "The defaults are set up for Chinese speakers working in English. Both your native language and the language you are learning can be changed in settings.",
  },
  {
    q: "Which apps does it work in?",
    a: "Any app where you can select text: browsers, mail, chat, editors, documents. For text you cannot select, OCR reads it from the screen. Rewrites replace the selection in place after you confirm.",
  },
  {
    q: "Which Mac do I need?",
    a: `${site.minMacOS} (Sequoia) or later. ${site.name} is a native app that lives in the menu bar, with an optional main window for history, saved words and review.`,
  },
]

export function Faq() {
  return (
    <section
      id="faq"
      aria-labelledby="faq-title"
      className="px-4 py-20 md:py-28"
    >
      <SectionHeading
        id="faq-title"
        eyebrow="FAQ"
        title="Questions, answered."
      />
      <Accordion className="mx-auto mt-12 max-w-3xl bg-card md:mt-16">
        {questions.map(({ q, a }) => (
          <AccordionItem key={q} value={q}>
            <AccordionTrigger className="px-6 py-5 text-[16px] hover:no-underline">
              {q}
            </AccordionTrigger>
            <AccordionContent className="px-2 pb-5 text-[15px] leading-relaxed text-muted-foreground">
              {a}
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </section>
  )
}
