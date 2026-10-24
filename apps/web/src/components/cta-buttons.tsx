import { buttonVariants } from "@workspace/ui/components/button"
import { cn } from "@workspace/ui/lib/utils"

import { site } from "@/lib/site"

function LaptopGlyph() {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="3" width="10" height="7" rx="1.2" />
      <path d="M1.5 13h13" />
    </svg>
  )
}

function GitHubGlyph() {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M5.5 4.5 2 8l3.5 3.5M10.5 4.5 14 8l-3.5 3.5M9 3l-2 10" />
    </svg>
  )
}

export function CtaButtons({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "flex flex-col items-stretch gap-3 sm:flex-row sm:items-center",
        className
      )}
    >
      <a
        href={site.downloadUrl}
        className={cn(
          buttonVariants({ size: "lg" }),
          "h-12 gap-2 px-6 text-[15px] shadow-[0_8px_24px_-8px] shadow-primary/60"
        )}
      >
        <LaptopGlyph />
        Download for macOS
      </a>
      <a
        href={site.githubUrl}
        className={cn(
          buttonVariants({ size: "lg", variant: "outline" }),
          "h-12 gap-2 px-6 text-[15px]"
        )}
      >
        <GitHubGlyph />
        View on GitHub
      </a>
    </div>
  )
}

export function CtaFootnote({ className }: { className?: string }) {
  return (
    <p className={cn("text-[13px] text-muted-foreground", className)}>
      Free and open source · {site.minMacOS} or later
    </p>
  )
}
