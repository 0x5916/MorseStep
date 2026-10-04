# MorseStep Learning System Contract Inventory

This document freezes and audits the contracts provided by the pure training and audio modules in `frontend/src/lib/` prior to introducing V2 learning architecture.

## 1. Existing Passage Session State Machine

**Location:** `frontend/src/lib/training/session.ts`  
**Purpose:** Models the lifecycle of an assessed 60-second continuous copy passage attempt.

### States (`SessionStatus`)

- `ready`: Initial state, session created via `createSession()`, exercise ready to play.
- `playing`: Audio playback is running on the audio engine.
- `paused`: Audio playback was temporarily suspended.
- `awaiting-check`: Playback ended or stopped; the answer textarea is enabled for typing and checking.
- `reviewed`: Attempt was scored and recorded via `transition(state, { type: 'check', result })`.
- `disposed`: Terminal state; session resources torn down.

### State Object (`SessionState`)

- `status: SessionStatus`: Current status.
- `attempt: number`: 1-based index incremented on `new-exercise` or `lesson-change`.
- `recordedAttempt: number | null`: Tracks which attempt index was checked to guarantee idempotent recording (`isAttemptRecorded()`).

### Supported Events (`SessionEvent`)

- `{ type: 'start' }`: `ready` → `playing`
- `{ type: 'pause' }`: `playing` → `paused`
- `{ type: 'resume' }`: `paused` → `playing`
- `{ type: 'stop' }`: `playing` | `paused` → `awaiting-check`
- `{ type: 'mode-change' }`: `playing` → `paused` (when toggling between drill and passage)
- `{ type: 'new-exercise' }`: Re-generates exercise for current lesson, increments `attempt`, returns to `ready`
- `{ type: 'lesson-change' }`: Re-generates exercise for new lesson, increments `attempt`, returns to `ready`
- `{ type: 'check'; result: AttemptResult }`: `awaiting-check` | `playing` | `paused` → `reviewed` with effect `{ kind: 'record-result', result }`
- `{ type: 'dispose' }`: Any state → `disposed`

### Coexistence Architecture Note

`session.ts` models a holistic, multi-word passage attempt. It will **coexist** with the new prompt-by-prompt guided session state machine (`training/v2/guided-session.ts`). `session.ts` will continue to drive the continuous copy tool under the Practice hub (`/morse/practice?mode=copy`).

---

## 2. Audio Engine & AudioPlan

**Locations:**

- `frontend/src/lib/training/timing.ts`
- `frontend/src/lib/audio/engine.ts`

### Timing Math (`FarnsworthTimings`)

All durations in `timing.ts` are defined in **fractional seconds** ($s$):

- `charDot = 1.2 / charWpm`
- `tFarn = (60 / effWpm - charDot * 31) / 19`
- `dash = charDot * 3`
- `symbolSpace = charDot`
- `letterSpace = tFarn * 3`
- `wordSpace = tFarn * 7`

### `AudioPlan` Contract

```ts
export interface AudioPlan {
  text: string; // Uppercase source text
  events: ToneEvent[]; // Array of { start: number, duration: number } (in seconds)
  totalDuration: number; // End of last tone relative to transmission start (seconds)
  startDelay: number; // Silence scheduled before first tone (seconds)
  fade: number; // Gain ramp length at tone edges (default 0.005s)
  frequency: number; // Tone pitch in Hz (e.g. 600)
  volume: number; // Master gain scalar 0.0-1.0
}
```

### `AudioEngine` Interface & Lifecycle

- `play(plan: AudioPlan): void`: Lazily initializes Web Audio `AudioContext` on first user gesture. Schedules tone oscillators and gain nodes on the audio timeline.
- `pause(): Promise<void>` / `resume(): Promise<void>`: Suspends/resumes `AudioContext`.
- `stop(options?: { notify?: boolean }): Promise<void>`: Tears down active context, increments playback generation counter to prevent stale ended callbacks.
- `dispose(): Promise<void>`: Silently terminates all audio resources.
- `subscribe(listener: (event: 'ended') => void): () => void`: Registers completion callbacks.
- `isActive(): boolean`, `isPaused(): boolean`, `elapsed(): number`: Query methods.

---

## 3. Existing Legacy Progress Storage and Payloads

**Locations:**

- `frontend/src/lib/progressSync.ts`
- `frontend/src/lib/storageKeys.ts`
- `frontend/src/lib/api.ts`

### Legacy Outbox Queue Format (`ProgressPayload`)

Stored in `localStorage` under `CW_STORAGE_KEYS.progressQueue` (`cw.progress.queue.v1`):

```ts
type ProgressPayload = {
  lesson: number; // 1-based lesson index
  char_wpm: number; // Character speed
  eff_wpm: number; // Effective speed
  accuracy: number; // 0.0 - 1.0 (CER based)
  client_created_at: string; // ISO timestamp of attempt completion
  username?: string; // Authenticated user if available
  queued_at: string; // ISO timestamp when queued
};
```

Queue limit is clamped to `MAX_QUEUE_SIZE = 500`. Uploads are sent via HTTP PUT to `/v1/cw/progress` via `submitProgress()` in `api.ts`.

### Storage Keys (`storageKeys.ts`)

- `AUTH_STORAGE_KEYS`:
  - `accessToken: 'access_token'`
  - `refreshToken: 'refresh_token'`
  - `username: 'username'`
- `CW_STORAGE_KEYS`:
  - `lesson: 'learn.lesson'`
  - `cwSettings: 'cw.settings.v1'`
  - `cwSettingsUpdatedAt: 'cw.settings.updated_at.v1'`
  - `pageSettingsUpdatedAt: 'cw.page_settings.updated_at.v1'`
  - `progressQueue: 'cw.progress.queue.v1'`
- `UI_STORAGE_KEYS`:
  - `theme: 'theme'`
  - `quickstartDismissed: 'learn.quickstart.dismissed'`
  - `trainerMode: 'learn.practice_mode'`
  - `trainerIntroLesson: 'learn.intro.lesson'`

---

## 4. Compatibility Surfaces & Module Roles

| Module                                  | Current Role                                         | V2 Evolution Plan                                                                                            |
| --------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `frontend/src/lib/morse.ts`             | Facade re-exporting training functions               | **Preserve as compatibility surface** for existing callers.                                                  |
| `frontend/src/lib/training/sequence.ts` | Koch sequence array (`LESSONS`) & `MORSE` dictionary | **Extend / Reuse as-is**. Canonical source of truth for character ordering.                                  |
| `frontend/src/lib/training/timing.ts`   | Farnsworth timing & `AudioPlan` generation           | **Extend / Reuse as-is**. Produces plans for both single prompts and passages.                               |
| `frontend/src/lib/training/exercise.ts` | Random timed passage generation                      | **Preserve for Practice Mode**. Move passage generation into continuous copy practice.                       |
| `frontend/src/lib/training/session.ts`  | Passage attempt state machine                        | **Preserve for Practice Mode**. Coexists with V2 prompt state machine.                                       |
| `frontend/src/lib/training/result.ts`   | `AttemptResult` & `ResultRecorder` port              | **Preserve**. V2 introduces richer prompt attempt events while keeping this port for passage results.        |
| `frontend/src/lib/score.ts`             | CER calculation & word diffing (`diffWords`)         | **Preserve for Practice Mode**. Prompt scoring will use exact character matching and latency classification. |
| `frontend/src/lib/progressSync.ts`      | Legacy outbox sync to `/cw/progress`                 | **Preserve during migration**. Coexists with V2 IndexedDB outbox until B3 sync cutover.                      |
| `frontend/src/lib/audio/engine.ts`      | Web Audio engine                                     | **Reuse as-is**. Shared by both passage player and guided prompt session controller.                         |
