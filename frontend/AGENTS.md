# Frontend Instructions for Coding Agents

This guide defines frontend architecture rules and conventions for MorseStep / OpenCW (`frontend/`).

## 1. Core Architecture & Boundaries

- **Static Prerender (`adapter-static`):** Every route is prerendered to static HTML at build time for all 5 locales. There is no server runtime in production.
- **Browser-Only Isolation:** Guard all access to `window`, `document`, `localStorage`, `indexedDB`, and Web Audio (`AudioContext`) with `browser` checks or in `onMount`. Never execute browser APIs at module top-level or during prerender.
- **Strict Layer Separation:**
  - `src/lib/training/`: Pure TypeScript domain logic (Koch curriculum, timing math, lesson builder, attempt scoring, mastery reducer, scheduler, state machines). No Svelte, DOM, or storage dependencies.
  - `src/lib/audio/`: Web Audio engine scheduling `AudioPlan` on the native timeline.
  - `src/lib/data/`: IndexedDB foundation, repositories, and migration modules.
  - `src/lib/components/`: Presentation components that receive derived display state and emit user intent. Components must NEVER calculate mastery, schedule audio nodes, or query IndexedDB directly.

## 2. Svelte 5 Conventions

- Use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`).
- Never use Svelte 4 legacy syntax (`let:` slots, `<slot />`, `export let`, writable store syntax where runes apply).
- Use untrack inside `$effect` when reading reactive state that should not trigger re-runs.
- Favor explicit function callbacks / rune properties for component events over deprecated `createEventDispatcher`.

## 3. Localization (Paraglide)

- **Source of Truth:** Translation files live in `messages/{en,de,ja,zh-Hans,zh-Hant}.json`.
- **NEVER edit generated files** in `src/lib/paraglide/`.
- When adding or changing translation keys, update all five locale catalogs and run `npm run messages:validate` and `npm run check`.
- Preserve full sentence context for translators; never concatenate localized sentence fragments.

## 4. Visual System & Styling

- **Design Language:** Warm neutral surfaces, amber interaction accent (`--accent`, `--accent-cta`), semantic status tokens (`--status-good`, `--status-ok`, `--status-bad`, `--status-extra`), flat surfaces, 2–6px radii (`--radius-*`), 4px spacing rhythm (`--space-*`).
- **All Color Literals in `src/app.css`:** Never hard-code hex colors or arbitrary utility colors in `.svelte` files. Read `var(--token)`.
- Cards remain flat and do not hover/lift unless the entire element is an interactive link or button.
- Icons: Use Lucide icons (`@lucide/svelte`) already installed. Do not use emoji as UI icons.

## 5. Sound-First & Accessibility Non-Negotiables

- **Sound-First Learning:** Assessed recognition must NEVER display dot-dash notation, Morse spelling, or animated equalizers that decode the answer during recall.
- **Non-Color Feedback:** Success and error states must always include text and icons (e.g., checkmark / cross), never color alone.
- **Touch Target Size:** Primary interactive training targets must be at least 44 × 44 CSS px (prefer 48 × 48 px) with at least 8 px spacing.
- **Keyboard Navigation:**
  - `Space`: Replay active prompt (guarded against default scrolling and text input composition).
  - `Enter`: Submit answer or continue from feedback.
  - Full keyboard focusability with visible `--focus-ring`. No keyboard traps.
- **Motion:** Support `prefers-reduced-motion: reduce` by suppressing animations and using static state transitions.

## 6. Verification Commands

Always run verification with Node 26 (`export PATH="/opt/homebrew/opt/node/bin:$PATH"`):

```sh
npm run test           # Vitest unit tests
npm run verify         # Messages, SEO, svelte-check, script checks, Vitest
npm run lint           # Prettier formatting + ESLint
npm run build          # Static prerender build
```
