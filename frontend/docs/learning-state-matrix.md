# MorseStep Learning State Matrix

This document defines the exhaustive state matrix required for each component in the learning flow, per section 7.3 of `morsestep-uiux-agent-spec.md`.

| Component                           | Required States                                                           | Test & Verification Strategy                                                       |
| ----------------------------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| **LearnHero**                       | `new`, `next`, `review-due`, `resume`, `complete`, `loading`, `error`     | Verify single dominant action, duration estimate, and wrapping of localized text.  |
| **CoursePath** / **CoursePathItem** | `stable`, `current`, `review`, `available`, `locked`, `legacy-unverified` | Verify icon + shape + text labels for all states; keyboard roving focus.           |
| **SessionShell**                    | `idle`, `active`, `paused`, `exit-prompt`                                 | Verify navigation hidden, `100dvh` stage, safe exit dialog on interrupt.           |
| **SessionProgress**                 | `step-progress` (e.g. 4/12), `completion-ratio`                           | Accessible progressbar attributes (`aria-valuenow`, `aria-valuemax`).              |
| **AudioPrompt**                     | `ready`, `playing`, `answer-ready`, `paused`, `replaying`, `audio-error`  | Large replay target (>=48px); sound-first (no answer hints); Space key guard.      |
| **AnswerInput**                     | `disabled`, `empty`, `composing`, `valid`, `submitting`, `restored`       | Desktop auto-focus; mobile software keyboard safe; IME handling.                   |
| **CharacterGrid**                   | `idle`, `focused`, `selected`, `correct`, `incorrect`, `disabled`         | Stable grid cells; roving tabindex; minimum 48px touch targets.                    |
| **PromptFeedback**                  | `automatic`, `developing`, `incorrect`, `missing`, `audio-error`          | Non-color icons (check/x); expected vs entered comparison; accessible live region. |
| **ContrastRepair**                  | `listening-A`, `listening-B`, `answering`, `resolved`                     | Unassisted A/B comparison without auto-overlapping audio; stable left/right slots. |
| **SessionResult**                   | `unlock`, `review`, `incomplete-data`, `offline-saved`, `sync-error`      | Progression headline; metrics ledger; visible "Finish for today" action.           |
| **SyncStatus**                      | `local-only`, `pending`, `syncing`, `synced`, `auth-required`, `error`    | Subtle non-blocking status indicator with retry option.                            |
| **ExitSessionDialog**               | `open`, `closing`, `focus-trapped`                                        | Standard accessible modal with confirm discard / cancel actions.                   |
