import { createFileRoute } from "@tanstack/react-router"

import { LandingPage } from "@/components/landing-page"
import { site } from "@/lib/site"

const title = `${site.name} — ${site.headline}`

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title },
      { name: "description", content: site.description },
      { property: "og:type", content: "website" },
      { property: "og:site_name", content: site.name },
      { property: "og:title", content: title },
      { property: "og:description", content: site.description },
      { name: "twitter:card", content: "summary" },
      { name: "twitter:title", content: title },
      { name: "twitter:description", content: site.description },
    ],
  }),
  component: LandingPage,
})
