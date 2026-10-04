# MorseStep Learning UI Specification

This document summarizes the visual, interaction, and accessibility contracts for MorseStep learning surfaces, derived from `morsestep-uiux-agent-spec.md`.

## 1. Visual Language & Tokens

- **Warm Neutral Surfaces:** Flat surfaces using `--bg-base`, `--bg-surface`, `--bg-inset`.
- **Single Interactive Accent:** Amber (`--accent`, `--accent-cta`, `--accent-cta-h`, `--on-accent`).
- **Semantic Statuses:**
  - Stable / Correct: `--status-good`
  - Review / Developing: `--status-ok`
  - Error / Incorrect: `--status-bad`
  - Info / Secondary: `--status-extra`
- **Learning Aliases:**
  - `--learning-current`: `var(--accent)`
  - `--learning-stable`: `var(--status-good)`
  - `--learning-review`: `var(--status-ok)`
  - `--learning-error`: `var(--status-bad)`
  - `--learning-info`: `var(--status-extra)`
  - `--session-max-width`: `42rem`
  - `--answer-target-min`: `3rem` (48px)
- **Compact Radii:** 2–6px (`--radius-xs` to `--radius-lg`). No pill containers for entire lesson cards.
- **Elevation:** Flat by default; elevation (`--shadow-overlay`) reserved for modals/dialogs.

## 2. Interaction & Keyboard Map

| Key             | Session Action                                        | Guard                                                                                            |
| --------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Space           | Play / Replay current prompt sound                    | Prevent default page scroll; not during text composition; not when focused control expects Space |
| Enter           | Submit valid answer or Continue to next prompt        | Guarded against double-submit                                                                    |
| Escape          | Pause active session or open Exit confirmation dialog | Never immediately discard without confirmation                                                   |
| 1–9 / Letters   | Select matching answer option in grid mode            | Valid options only                                                                               |
| Tab / Shift+Tab | Predictable keyboard traversal                        | No keyboard trap                                                                                 |

## 3. Touch & Target Sizes

- Primary touch targets for replay and character choices are at least **44 × 44 CSS px**, preferably **48 × 48 CSS px** (`--answer-target-min`).
- At least 8px spacing between active interactive targets.
- Touch grid target positions remain stable across consecutive prompts.

## 4. Sound-First Assessment & Non-Color Rules

- Under NO circumstances may Morse dots/dashes, spellings, or waveform equalizer animations be displayed while the prompt is being assessed.
- Success and error feedback must combine semantic icons, text, and color—never color alone.
- Feedback supports reduced motion (`prefers-reduced-motion: reduce`).
