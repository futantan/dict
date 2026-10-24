import { cn } from "@workspace/ui/lib/utils"
import type { ReactNode } from "react"

export function Eyebrow({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <p
      className={cn(
        "font-mono text-[11.5px] font-medium tracking-[0.14em] text-brand uppercase",
        className
      )}
    >
      {children}
    </p>
  )
}

export function SectionHeading({
  id,
  eyebrow,
  title,
  lede,
  className,
}: {
  id?: string
  eyebrow: string
  title: ReactNode
  lede?: ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        "mx-auto flex max-w-3xl flex-col items-center gap-4 text-center",
        className
      )}
    >
      <Eyebrow>{eyebrow}</Eyebrow>
      <h2
        id={id}
        className="font-display text-[clamp(2.1rem,5vw,3.4rem)] leading-[1.05] font-medium text-balance"
      >
        {title}
      </h2>
      {lede ? (
        <p className="max-w-xl text-[17px] leading-relaxed text-pretty text-muted-foreground">
          {lede}
        </p>
      ) : null}
    </div>
  )
}
