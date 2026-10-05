# MorseStep UI and UX audit and plan

This audit guides frontend improvements to the sound-first Morse learning experience. The priority is to make the next useful action clear, keep session controls trustworthy, and preserve the existing visual language. Work proceeds in bounded packets, with the first packet focused on the Learn dashboard.

## Scope and evidence

The findings below describe baseline commit `1d5c1c2`, reviewed on 5 October 2026, across routes, shared components, training logic, and repository contracts. Source line references point to that baseline. They are not an exhaustive security audit. Backend schemas, API behavior, authentication, dependencies, and deployment configuration remain outside this design packet.

Browser observations must be distinguished from source findings. The acceptance checks below require interaction in the browser; reading a component does not establish its rendered appearance or prove that a complete session works.

## Existing foundations

The project already provides SvelteKit 5, a static build for five locales, an isolated audio engine, pure training logic, IndexedDB repositories, and reusable learning components. Preserve these layers rather than introducing another framework or duplicating domain logic in presentation components.

The shared design system in `src/app.css` defines warm surfaces, semantic feedback, spacing, typography, visible focus, and reduced motion. The learning contracts in `docs/learning-ui-spec.md` and `docs/learning-state-matrix.md` remain acceptance requirements, especially the prohibition on answer-revealing Morse notation during assessment.

## Source review findings

| Priority | Finding and consequence                                                                                                                                                                  | Evidence                                                                                                                                                |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0       | Next and repeat navigate within the same session route, while the controller initializes only on mount. Explicit session intents need to create or restore the correct controller state. | `src/routes/morse/learn/session/+page.svelte:33,111–117`                                                                                                |
| P0       | Resume navigates by lesson rather than saved session identity; discard clears only visible state. Labels imply persistence behavior that the handlers do not perform.                    | `src/routes/morse/learn/+page.svelte:104–110`                                                                                                           |
| P0       | Contrast repair exposes a second sound action with an empty handler; playing the expected sound also depends on controller phase.                                                        | `src/routes/morse/learn/session/+page.svelte:152–167`                                                                                                   |
| P1       | First-run guidance tests an empty mastery map even though new K and M entries populate it. Completion tests the last unlocked lesson rather than completed mastery.                      | `src/routes/morse/learn/+page.svelte:27–34,70–90`                                                                                                       |
| P1       | Learn, Practice, Progress, and session components mix localized navigation with hard-coded English copy and accessible labels.                                                           | `src/routes/morse/learn/+page.svelte:115–156`; `src/routes/morse/practice/+page.svelte:53–112`; `src/lib/components/learning/AudioPrompt.svelte:48–104` |
| P1       | Exit confirmation claims modal semantics without initial focus, Tab containment, or focus restoration. Space replay excludes text inputs but can override other focused controls.        | `src/lib/components/learning/ExitSessionDialog.svelte:23–50`; `src/lib/components/learning/AudioPrompt.svelte:29–40`                                    |
| P1       | The layout and training hubs both own `.page-content`, duplicating padding and mobile navigation clearance. The Learn skeleton uses a fixed width that can exceed a small card.          | `src/routes/+layout.svelte:340–349`; Learn `:118`, Practice `:28`, Progress `:121`; `src/lib/components/learning/LearnHero.svelte:182–184`              |
| P2       | The course path initially renders every lesson, placing the free-practice route after a long list. Interactive children also need consistent list semantics.                             | `src/lib/components/learning/CoursePath.svelte:44–55`; `src/lib/components/learning/CoursePathItem.svelte:36–81`; Learn `:151`                          |
| P2       | Progress estimates minutes as completed sessions multiplied by four and hides storage failures after logging them. Zero data can be confused with an error.                              | `src/routes/morse/progress/+page.svelte:44–49,106–109`                                                                                                  |
| P2       | Navigation and SEO use OpenCW while training titles use MorseStep. The home preview represents an older trainer pattern.                                                                 | `src/routes/+layout.svelte:245`; `src/lib/seo.ts:12`; `src/routes/+page.svelte:24–58`                                                                   |

The curriculum has 39 lessons introducing 40 characters (`src/lib/training/sequence.ts:9–49`). Review actions should derive their lesson limit from that source instead of hard-coding lesson 40 (`LearnHero.svelte:72`).

## Design direction

Keep the established dark palette and its existing light-theme equivalents. Components read these roles through shared CSS tokens:

| Role                         | Existing dark value     |
| ---------------------------- | ----------------------- |
| Base and surface             | `#17140f` and `#1f1b14` |
| Primary text and interaction | `#f2ede3` and `#f2a33c` |
| Stable and review            | `#63c08d` and `#d9a216` |

Keep the existing UI font family; reserve monospace for characters. Preserve flat surfaces, 2–6px radii, semantic icons with text, theme support, visible focus, and the 4px spacing rhythm.

Make Learn left-aligned and action-led. A short header establishes the goal; the recommendation supplies one dominant action and its duration. Place free practice directly after the compact course overview. Show one previous lesson, the current lesson, and two upcoming lessons by default, with older and later lessons available through labeled disclosures. Status words and icons explain progress without relying on color.

```text
Learn Morse by ear
Build sound recognition in short sessions

[ Recommended lesson                   ]
[ Lesson N / New character              ]
[ About 4 min          Start lesson     ]

Your course                 N of 39 unlocked
> Earlier lessons
  Lesson N-1       Mastered
  Lesson N         Current lesson
  Lesson N+1       Not unlocked yet
  Lesson N+2       Not unlocked yet
> Upcoming lessons

Choose characters or a longer passage
Explore practice
```

## First implementation packet

The focused Learn dashboard packet removes Learn's nested page padding, localizes its header, course statuses, disclosure labels, and practice action across all five catalogs, and compacts the path around the current lesson. It adds semantic list structure and current-step information, and constrains the recommendation skeleton to its available width. Empty-device onboarding now uses the existing 60-day attempt history rather than mastery-map size; it is not a lifetime history check.

This packet improves orientation and browsing. It does not complete training localization or change mastery thresholds, final-lesson completion, saved-session behavior, audio scheduling, or backend contracts.

## Subsequent bounded packets

1. **P0 session intents:** Implement and verify next, retry, resume by saved identity, persistent discard, and both contrast-repair sounds. Provide visible initialization and audio errors with working recovery actions.
2. **P1 progression:** Handle lifetime first-run history and final-lesson completion guidance; derive review bounds from the curriculum. Cover new, returning, review-due, and genuinely complete states with focused domain tests.
3. **P1 localization:** Translate remaining recommendation, session, practice, result, and progress copy and accessible names using complete messages in all five catalogs.
4. **P1 accessibility:** Complete dialog focus handling, protect native Space behavior on focused controls and composition, and verify keyboard paths, touch targets, and reduced motion.
5. **P2 progress evidence:** Show recorded duration or clearly labeled estimates, distinguish empty data from failed loading, and offer recovery. Then align product naming and home content with the current learning flow.

## Acceptance and verification

For the first packet, inspect Learn at 320px, 390px, and desktop widths in both themes. Confirm one page-padding owner, no horizontal overflow, a nearby current lesson and practice action, working previous/upcoming disclosures, and no disclosure containing the current item. Inspect translated text wrapping, keyboard focus, list semantics, and current-step announcement.

Run Node 26 verification with `npm run verify`, `npm run lint`, and `npm run build`. Record exit codes, test counts, and `git status --short` alongside the change. Verify loaded and skeleton states in the browser; passing static checks does not establish session behavior. Later session packets must include browser interaction through their complete intent and recovery paths.

## Verification results

The first packet passes lint and the static production build. Full verification remains blocked by the existing local test setup: Vitest is declared and locked but absent from `node_modules`; IndexedDB tests import `fake-indexeddb`, which is absent from both the manifest and lockfile. No unit tests executed. Resolving the undeclared test dependency requires a separate approved dependency change.

| Check                   | Exit | Evidence                                                                                                                                                   |
| ----------------------- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run verify`        | 1    | Messages passed: 368 keys across five locales; SEO passed: 25 URLs. Svelte check reported 25 errors in existing test files from missing test dependencies. |
| `npm run test`          | 127  | Vitest executable missing; 0 tests ran.                                                                                                                    |
| `npm run check:scripts` | 0    | TypeScript script validation passed.                                                                                                                       |
| `npm run lint`          | 0    | Formatting and ESLint passed.                                                                                                                              |
| `npm run build`         | 0    | Static prerender build generated successfully.                                                                                                             |

The Svelte analyzer reported no issues for CoursePath, CoursePathItem, or LearnHero. The Learn route reported three navigation warnings for the existing `localizedHref` wrapper; locale-aware destinations were verified in the browser. No navigation helper changes were made.

Browser checks confirmed empty-device introductory guidance, three nearby rows at lesson 1, access to all 39 rows when expanded, keyboard Space toggling the disclosure, and the current lesson staying outside disclosures. At 320px and 390px, document width matched the viewport. The current lesson row measured about 70px high and the disclosure 48px. English dark mode and German light mode were inspected; the remaining recommendation copy is still English, as documented in the localization packet. Later-lesson slicing was reviewed independently from source; persisted returning-learner and completion states were not exercised.

The final working tree contains nine modified frontend source/catalog files and this new audit document. Backend, dependency manifests, and deployment files have no changes. Command evidence and the final `git status --short` are captured in the chat tool output.
