import { Faq } from "@/components/faq"
import { Features } from "@/components/features"
import { Hero } from "@/components/hero"
import { Privacy } from "@/components/privacy"
import { SiteFooter } from "@/components/site-footer"
import { SiteHeader } from "@/components/site-header"
import { WordBook } from "@/components/word-book"

export function LandingPage() {
  return (
    <div className="overflow-x-clip">
      <SiteHeader />
      <main>
        <Hero />
        <WordBook />
        <Features />
        <Privacy />
        <Faq />
      </main>
      <SiteFooter />
    </div>
  )
}
