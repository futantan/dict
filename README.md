# Dict

Dict is a native macOS menu bar app for people who use a second language every day.
"Dict" is a placeholder name.
Everything is licensed under GPL-3.0-or-later.

## Layout

- `apps/macos/` is the Swift app; run its `make` targets from that directory (see its README).
- `apps/web/` is the website, built with TanStack Start, Tailwind and shadcn.
- `packages/ui/` holds the shared shadcn components and theme for the web.

## Web

The web workspace uses pnpm and Node 24 or later.

```sh
pnpm install
pnpm -F web dev   # http://localhost:3000
pnpm check        # oxfmt, oxlint, typecheck and vitest
pnpm build
```

Add shadcn components from `apps/web` with `pnpm dlx shadcn@latest add <name>`; they land in `packages/ui`.
