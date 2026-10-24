import { cn } from "@workspace/ui/lib/utils"

import { site } from "@/lib/site"

export function DownloadButton({ className }: { className?: string }) {
  return (
    <a
      href={site.downloadUrl}
      className={cn(
        "shadow-button group inline-flex h-10 items-center gap-1.5 rounded-full bg-primary pr-4 pl-5 text-[15px] font-medium text-primary-foreground transition-colors hover:bg-primary/90",
        className
      )}
    >
      Download for macOS
      <svg
        viewBox="0 0 16 16"
        aria-hidden="true"
        className="size-3.5 transition-transform group-hover:translate-x-0.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="m6 3.5 4.5 4.5L6 12.5" />
      </svg>
    </a>
  )
}
