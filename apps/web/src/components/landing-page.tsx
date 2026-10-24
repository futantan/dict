import { ClosingCta, SiteFooter } from "@/components/closing"
import { Faq } from "@/components/faq"
import { Features } from "@/components/features"
import { Hero } from "@/components/hero"
import { HowItWorks } from "@/components/how-it-works"
import { Privacy } from "@/components/privacy"
import { SiteHeader } from "@/components/site-header"

export function LandingPage() {
  return (
    <div className="relative isolate overflow-x-clip">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[720px] bg-[radial-gradient(60%_60%_at_50%_0%,color-mix(in_oklab,var(--brand)_14%,transparent),transparent_70%)]"
      />
      <SiteHeader />
      <main>
        <Hero />
        <Features />
        <HowItWorks />
        <Privacy />
        <Faq />
        <ClosingCta />
      </main>
      <SiteFooter />
    </div>
  )
}
