# OpenCW Frontend

Web frontend for OpenCW — a Morse code (CW) training site with Koch-method lessons,
progress tracking, and a community forum.

Built with SvelteKit (Svelte 5 runes), TypeScript, Paraglide i18n (en, de, ja, zh-Hans,
zh-Hant) and Tailwind CSS (preflight; most UI is plain CSS/utility classes in `src/app.css`).
The site is fully static: every page is prerendered for all five locales at build time
and served as plain files — there is no server runtime.

## Requirements

- Node.js 26 (see the `Dockerfile`; `npm` 11+ recommended)
- A running OpenCW API (defaults to `http://localhost:8080/v1` via `PUBLIC_API_BASE`)
- TypeScript is held at 6.x: the TypeScript 7 native compiler has no stable API
  yet, so svelte-check and typescript-eslint still require TypeScript 6.

## Setup

```sh
npm ci
cp example.env .env   # adjust PUBLIC_API_BASE if needed
npm run dev
```

## Scripts

| Script                      | Purpose                                                         |
| --------------------------- | --------------------------------------------------------------- |
| `npm run dev`               | Vite dev server with HMR                                        |
| `npm run build`             | Static production build (prerendered site in `build/`)          |
| `npm run start`             | Serve the production build locally (`vite preview`)             |
| `npm run preview`           | Preview the production build                                    |
| `npm run check`             | `svelte-kit sync` + `svelte-check` (TypeScript/Svelte errors)   |
| `npm run check:scripts`     | `tsc` over `scripts/` (validators are outside the app tsconfig) |
| `npm run verify`            | All gates in order: messages, SEO, app check, scripts check     |
| `npm run lint`              | Prettier check + ESLint                                         |
| `npm run format`            | Prettier write                                                  |
| `npm run messages:validate` | Message gate: locale parity, missing/extra keys                 |
| `npm run seo:validate`      | SEO gate: sitemap coverage, metadata lengths, duplicate titles  |
| `npm run icons`             | Regenerate favicons/social images from the source SVG           |

## Project layout

```
messages/          Paraglide translation catalogs (one JSON per locale)
scripts/           Icon generation + message/SEO validators
src/
  app.css          Design tokens, base styles, shared UI classes
  hooks.server.ts  Paraglide middleware (dev server + prerendering only)
  lib/
    api.ts         Typed API client (settings, user, forum, progress)
    auth.ts        Token handling (login/register/refresh/logout) + apiFetch
    cookies.ts     One-time migration from legacy preference cookies
    cwSync.ts      Client/server CW + page settings reconciliation
    errorCode.ts   API error-code extraction
    errorLocalization.ts  Error code → localized message
    format.ts      Date / lesson / percentage formatting helpers
    i18n.svelte.ts Locale state + locale-aware hrefs
    locale.ts      Locale matching + display labels
    morse.ts       Koch lessons, Morse table, Farnsworth timing
    progressSync.ts Offline-first progress queue
    score.ts       Accuracy scoring, word-level diff, grade thresholds
    seo.ts         Route metadata, sitemap URL builder (used by scripts)
    storageKeys.ts localStorage key registry
    theme.ts       Theme normalization + apply helpers
    components/    Shared UI (auth card, dropdown, Morse player, alerts, …)
  routes/          Pages (home, about, learn, login, register, profile,
                   settings, the forum list + /forum/[id] threads, and legacy
                   /morse redirects)
```

`/forum` is backed by the API: a cursor-paginated thread list with category
filters and an inline composer, plus client-rendered thread pages at
`/forum/[id]` with nested replies, author-only deletes and tombstones. Thread
IDs only exist at runtime, so thread pages are not prerendered: deep links are
served the adapter-static fallback by `nginx.conf`, which returns HTTP 200 for
forum deep links so shared links open and unfurl correctly.

## Internationalization

- Message keys live in `messages/*.json`; all locales must define the same keys.
- Paraglide output is generated into `src/lib/paraglide/` (gitignored) using the
  shared options in `scripts/paraglide-options.ts`. `npm run check` compiles it
  before `svelte-check`, and `npm run build` compiles it through the Vite plugin.
  Run either command after changing keys in `messages/*.json`.
- URLs are localized (`/de/...`, `/ja/...`, …). Every locale variant is
  prerendered, so the active locale always comes from the URL.
- Bare paths (`/about`) and legacy `/morse` URLs exist only in the base locale in
  the build; once the app hydrates they redirect to the visitor's preferred
  locale (stored in `localStorage`). Existing visitors' legacy preference
  cookies are migrated once and then removed.

## Validation gates

`npm run verify` runs every gate in order, and the Docker build runs it before
`vite build`, so a missing translation, a drifted noindex route or a type error
cannot ship:

```sh
npm run verify
```

- `messages:validate` — locale parity, placeholder consistency, missing and
  unreferenced message keys.
- `seo:validate` — sitemap coverage for all locales and indexable public routes,
  noindex exclusion, title/description lengths, duplicate titles, and the nginx
  locale list.
- `check` — `svelte-kit sync` + `svelte-check`.
- `check:scripts` — `tsc` over `scripts/**`, which the app tsconfig does not cover.

## Docker

```sh
docker build \
  --build-arg PUBLIC_API_BASE=https://api.example.com/v1 \
  --build-arg PRERENDER_ORIGIN=https://opencw.net \
  -t opencw-frontend .
docker run -p 3000:80 opencw-frontend
```

The image builds the static site and serves it with nginx; the build stage runs
`npm run verify` before `npm run build`. Both arguments are
build-time values: `PUBLIC_API_BASE` is baked into the client bundle through
`$env/static/public`, and `PRERENDER_ORIGIN` (default `https://opencw.net`) into
the canonical/hreflang/Open Graph URLs and `sitemap.xml`. The bundled nginx
config serves forum thread deep links (`/<locale>/forum/<id>`) the SPA fallback
with a 200 status; every other unknown URL keeps its 404 status.
