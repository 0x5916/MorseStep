<script lang="ts">
  import { browser } from '$app/environment';
  import {
    calculateDuration,
    generateTimedLesson,
    getLessonChars,
    LESSONS,
    MORSE
  } from '$lib/morse';
  import { formatClock, percentage } from '$lib/format';
  import MorsePlayer from '$lib/components/MorsePlayer.svelte';
  import ResultOverlay from '$lib/components/ResultOverlay.svelte';
  import GuestNotice from '$lib/components/GuestNotice.svelte';
  import { onDestroy, onMount, tick, untrack } from 'svelte';
  import { ArrowLeft, ChevronLeft, ChevronRight } from '@lucide/svelte';
  import { CW_STORAGE_KEYS, UI_STORAGE_KEYS } from '$lib/storageKeys';
  import { langPreference, localizedHref as href } from '$lib/i18n.svelte';
  import { SCORE_GOOD, SCORE_OK, score, diffWords } from '$lib/score';
  import type { DiffToken } from '$lib/score';
  import { user } from '$lib/auth';
  import { saveProgressOfflineFirst } from '$lib/progressSync';
  import {
    normalizeLesson,
    readClientCwSettings,
    readClientPageSettings,
    restoreSettingsFromServer,
    saveClientCwSettings,
    syncSettingsToServer
  } from '$lib/cwSync';
  import * as m from '$lib/paraglide/messages';

  /** The playback controls the page drives from outside the player. */
  type PlayerHandle = {
    playNow: () => Promise<void>;
    stopNow: () => Promise<void>;
    isStarted: () => boolean;
  };

  let inputText = $state('');

  // The stored lesson can only be read in the browser (the site is fully
  // static), so start from the first lesson and restore it on mount below.
  let chosenLesson = $state(1);

  let result = $state(-1);
  let showOverlay = $state(false);
  let diffTokens = $state<DiffToken[]>([]);
  let showQuickStart = $state(false);
  let quickStartInstructionsOpen = $state(true);
  let charWpm = $state(20);
  let effWpm = $state(10);
  let freq = $state(600);
  let volume = $state(1);
  let startDelay = $state(0.5);
  let autoSyncTimeout: ReturnType<typeof setTimeout> | null = null;
  // Attempts for this visit only: the durable record lives in the progress
  // queue and on the profile page. The strip exists so a practice session has a
  // visible shape without touching any stored data.
  let attempts = $state<number[]>([]);
  let playing = $state(false);

  // Two distinct practices share this page: drilling a single character and
  // copying a timed passage. Only the active mode's controls are rendered, and
  // the learner's choice is remembered between visits. A lesson the learner has
  // not started here yet leads with the drill, so the newly introduced
  // character is practised by ear before it turns up in a passage.
  let mode = $state<'passage' | 'drill'>('drill');
  let introLesson = $state<number | null>(null);
  let modePassageEl = $state<HTMLInputElement | null>(null);

  // The passage stays hidden for the whole attempt and is only shown once the
  // copy has been checked — the listening exercise depends on not reading it.
  let sessionStarted = $state(false);
  let answerEl = $state<HTMLTextAreaElement | null>(null);
  // Two-step guard: an unfinished copy is never discarded by one stray click.
  let newExerciseArmed = $state(false);
  let newExerciseTimer: ReturnType<typeof setTimeout> | null = null;

  // Character drill: familiarisation with one character. The character and its
  // pattern stay on screen, playback plays that character, and the selector
  // changes both.
  let drillPlayer = $state<PlayerHandle | null>(null);
  let drillPlaying = $state(false);
  let drillPlayed = $state(false);

  // Character set popover.
  let charsetOpen = $state(false);
  let charsetEl = $state<HTMLDetailsElement | null>(null);

  $effect(() => {
    if (!browser) return;
    showQuickStart = localStorage.getItem(UI_STORAGE_KEYS.quickstartDismissed) !== '1';
  });

  onMount(() => {
    quickStartInstructionsOpen = !window.matchMedia('(max-width: 639px)').matches;
  });

  $effect(() => {
    if (!browser) return;
    const localCw = readClientCwSettings();
    charWpm = localCw.char_wpm;
    effWpm = localCw.eff_wpm;
    freq = localCw.freq;
    startDelay = localCw.start_delay;
  });

  async function dismissQuickStart() {
    showQuickStart = false;
    if (!browser) return;
    localStorage.setItem(UI_STORAGE_KEYS.quickstartDismissed, '1');

    if (window.matchMedia('(max-width: 639px)').matches) {
      await tick();
      const playButton = document.querySelector<HTMLButtonElement>('.player-play-btn');
      if (playButton) {
        const buttonTop = playButton.getBoundingClientRect().top + window.scrollY;
        const top = buttonTop - (window.innerHeight - playButton.offsetHeight) / 2;
        window.scrollTo({ top, behavior: 'instant' });
        playButton.focus({ preventScroll: true });
      }
    }
  }

  $effect(() => {
    if (!$user) return;
    restoreSettingsFromServer()
      .then(({ cw }) => {
        charWpm = cw.char_wpm;
        effWpm = cw.eff_wpm;
        freq = cw.freq;
        startDelay = cw.start_delay;
        saveClientCwSettings(cw);
      })
      .catch(() => {
        // Keep local defaults if server restore fails.
      });
  });

  // Restore the last used lesson and practice mode. This is a `pre` effect so it
  // runs before the persistence effects below can overwrite the stored values
  // with their defaults. It reads no reactive state: a lesson change later in
  // the session must never be stamped back to the stored one.
  $effect.pre(() => {
    if (!browser) return;

    const stored = localStorage.getItem(CW_STORAGE_KEYS.lesson);
    const parsed = Number.parseInt(stored ?? '', 10);
    const lesson = Number.isFinite(parsed) ? normalizeLesson(parsed, LESSONS.length) : 1;
    chosenLesson = lesson;

    // Coming back to a lesson that already ran the introduction restores the
    // mode the learner left, instead of walking them through it again.
    const storedMode = localStorage.getItem(UI_STORAGE_KEYS.trainerMode);
    const storedIntro = Number.parseInt(
      localStorage.getItem(UI_STORAGE_KEYS.trainerIntroLesson) ?? '',
      10
    );
    if (Number.isFinite(storedIntro)) introLesson = storedIntro;
    if ((storedMode === 'passage' || storedMode === 'drill') && storedIntro === lesson) {
      mode = storedMode;
    }
  });

  $effect(() => {
    const val = String(normalizeLesson(chosenLesson, LESSONS.length));
    localStorage.setItem(CW_STORAGE_KEYS.lesson, val);
  });

  // The mode switch is a preference, not a per-session choice.
  $effect(() => {
    if (!browser) return;
    localStorage.setItem(UI_STORAGE_KEYS.trainerMode, mode);
  });

  // The drill leads until the introduction has been seen for this lesson. The
  // learner can still switch at any time — this only decides where a lesson
  // starts, and it never runs twice for the same one.
  $effect(() => {
    if (!browser) return;
    const lesson = normalizeLesson(chosenLesson, LESSONS.length);
    if (introLesson === lesson) return;
    introLesson = lesson;
    localStorage.setItem(UI_STORAGE_KEYS.trainerIntroLesson, String(lesson));
    mode = 'drill';
  });

  let lessonText = $derived(generateTimedLesson(chosenLesson, 60, charWpm, effWpm));
  let currentLessonChars = $derived(getLessonChars(chosenLesson).split('').filter(Boolean));
  // Drill target: the newest character the lesson introduces. Lesson 1's
  // sequence ends with M, so that is where the default lands; the lesson effect
  // below keeps it right for every other lesson.
  let selectedLessonChar = $state((LESSONS[0] ?? '').slice(-1));
  let fullLessonPlayer = $state<PlayerHandle | null>(null);
  function regenerate() {
    // A fresh passage never plays under the previous one.
    if (playing) void stopPlayback();
    lessonText = generateTimedLesson(chosenLesson, 60, charWpm, effWpm);
    resetResultState({ clearInput: true });
  }

  async function checkResult() {
    result = score(lessonText, inputText);
    diffTokens = diffWords(lessonText, inputText);
    showOverlay = true;
    // Checking ends the attempt: stop the audio so the transport matches the
    // "Checked" state instead of running on behind the result.
    if (playing) void stopPlayback();
    // A pending discard stops being pending once the copy has been checked.
    newExerciseArmed = false;
    if (newExerciseTimer) clearTimeout(newExerciseTimer);
    attempts = [...attempts, result].slice(-20);
    if (result > 0) {
      saveProgressOfflineFirst({
        lesson: chosenLesson,
        char_wpm: charWpm,
        eff_wpm: effWpm,
        accuracy: result
      }).catch(() => {});
    }
  }

  let hasNextLesson = $derived(result >= SCORE_GOOD && chosenLesson < LESSONS.length);
  let hasPrevLesson = $derived(result < SCORE_OK && chosenLesson > 1);

  let attemptCount = $derived(attempts.length);
  let bestAttempt = $derived(attempts.reduce((best, value) => Math.max(best, value), 0));
  let averageAttempt = $derived(
    attempts.length === 0 ? 0 : attempts.reduce((sum, value) => sum + value, 0) / attempts.length
  );
  // Set composition, used by the lesson card and the character-set popover.
  const isLetter = (char: string) => /[A-Z]/.test(char);
  const isNumber = (char: string) => /[0-9]/.test(char);

  let letterChars = $derived(currentLessonChars.filter(isLetter));
  let numberChars = $derived(currentLessonChars.filter(isNumber));
  let symbolChars = $derived(
    currentLessonChars.filter((char) => !isLetter(char) && !isNumber(char))
  );
  // Fixed-height set preview: only the newest characters, so the card stays the
  // same height as the set grows.
  let latestChars = $derived(currentLessonChars.slice(-7));
  let learnedLabel = $derived(
    currentLessonChars.length === 1
      ? m.trainer_set_learned_one()
      : m.trainer_set_learned({ count: String(currentLessonChars.length) })
  );
  let lessonKindLabel = $derived(
    numberChars.length + symbolChars.length > 0
      ? m.trainer_lesson_mixed()
      : m.trainer_lesson_letters()
  );
  let drillMorse = $derived(
    (MORSE[selectedLessonChar] ?? '')
      .split('')
      .map((symbol) => (symbol === '.' ? '·' : '−'))
      .join('')
  );

  // The five steps of a copy session, with the current one marked.
  let flowSteps = $derived([
    { index: 0, label: m.trainer_flow_start },
    { index: 1, label: m.trainer_flow_listen },
    { index: 2, label: m.trainer_flow_type },
    { index: 3, label: m.trainer_flow_check },
    { index: 4, label: m.trainer_flow_review }
  ]);
  let flowIndex = $derived(
    !sessionStarted ? 0 : playing ? 1 : result >= 0 ? 4 : inputText.trim() === '' ? 2 : 3
  );

  // The send time the player will actually run for: the generator's 60 s target
  // is only approximate, so the header quotes the same clock the transport does.
  // Floored, not rounded, so both readouts agree to the second.
  let sendSeconds = $derived(Math.floor(calculateDuration(lessonText, charWpm, effWpm)));

  // One line per state, naming what to do next.
  let sessionStateText = $derived(
    result >= 0
      ? m.trainer_state_checked()
      : playing
        ? m.trainer_state_listening()
        : !sessionStarted
          ? m.trainer_state_ready()
          : inputText.trim() !== ''
            ? m.trainer_state_ready_check()
            : m.trainer_state_idle()
  );

  let newExerciseLabel = $derived(
    newExerciseArmed ? m.trainer_new_exercise_confirm() : m.trainer_try_again()
  );

  /**
   * New exercise is destructive once a copy has been typed: the first click
   * arms it, the second one discards. With an empty box it acts immediately.
   */
  function requestNewExercise() {
    // Unfinished work — a typed copy, or a session already under way — asks
    // first. A fresh, untouched exercise is replaced straight away.
    const unfinished = result < 0 && (inputText.trim() !== '' || sessionStarted);
    if (newExerciseTimer) clearTimeout(newExerciseTimer);

    if (!newExerciseArmed && !unfinished) {
      regenerate();
      return;
    }

    if (newExerciseArmed) {
      newExerciseArmed = false;
      regenerate();
      return;
    }

    newExerciseArmed = true;
    newExerciseTimer = setTimeout(() => (newExerciseArmed = false), 4000);
  }
  // Only the action that is next uses the amber fill: while the audio runs the
  // transport owns it, then the check does — until the copy has been checked.
  let isCheckPrimary = $derived(inputText.trim() !== '' && !playing && result < 0);

  function prevLesson() {
    chosenLesson -= 1;
    resetResultState({ clearInput: true });
    scheduleApiSync();
  }

  function nextLesson() {
    chosenLesson += 1;
    resetResultState({ clearInput: true });
    scheduleApiSync();
  }

  function resetResultState(options: { clearInput?: boolean } = {}) {
    if (options.clearInput) {
      inputText = '';
    }

    result = -1;
    diffTokens = [];
    showOverlay = false;
    // A new exercise starts hidden again: no transcript, locked answer box.
    sessionStarted = false;
  }

  function onLessonSelectChange() {
    result = -1;
    scheduleApiSync();
  }

  function onCwSettingInput() {
    saveClientCwSettings({ char_wpm: charWpm, eff_wpm: effWpm, freq, start_delay: startDelay });
    scheduleApiSync();
  }

  function scheduleApiSync() {
    if (!$user) return;
    if (autoSyncTimeout) clearTimeout(autoSyncTimeout);
    autoSyncTimeout = setTimeout(() => {
      void syncSettings();
    }, 1000);
  }

  async function syncSettings() {
    if (!$user) return;
    const cw = { char_wpm: charWpm, eff_wpm: effWpm, freq, start_delay: startDelay };
    const page = readClientPageSettings(chosenLesson, LESSONS.length, langPreference.value);
    try {
      await syncSettingsToServer(cw, page);
    } catch {
      // Keep training flow uninterrupted if sync fails.
    }
  }

  // The lesson decides the default target: the newest character it introduces.
  // Changing lesson updates it and stops whatever was playing.
  $effect(() => {
    const chars = currentLessonChars;
    untrack(() => {
      selectedLessonChar = chars.length === 0 ? '' : chars[chars.length - 1];
      // A new target starts fresh: back to "Play" from "Replay".
      drillPlayed = false;
      if (drillPlaying) void stopDrill();
    });
  });

  // The character-set popover behaves like the app's other floating panels:
  // Escape and outside clicks close it, and focus returns to its trigger.
  $effect(() => {
    if (!charsetOpen) return;

    function onDocumentClick(event: MouseEvent) {
      const target = event.target;
      if (charsetEl && target instanceof Node && !charsetEl.contains(target)) {
        charsetOpen = false;
      }
    }

    function onDocumentKeydown(event: KeyboardEvent) {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      charsetOpen = false;
      charsetEl?.querySelector('summary')?.focus();
    }

    document.addEventListener('click', onDocumentClick);
    document.addEventListener('keydown', onDocumentKeydown);
    return () => {
      document.removeEventListener('click', onDocumentClick);
      document.removeEventListener('keydown', onDocumentKeydown);
    };
  });

  function onAnswerInput(event: Event) {
    const value = (event.currentTarget as HTMLTextAreaElement).value;
    inputText = value.toUpperCase();
  }

  /** Playback started, whichever control started it (button, Space, replay). */
  function onSessionStart() {
    sessionStarted = true;
    playing = true;
    // Start → listen → type: the cursor belongs in the answer box whichever
    // control started the audio. The box stays disabled until the session has
    // started, so focus once that state has reached the DOM.
    void tick().then(() => answerEl?.focus());
  }

  async function playSession() {
    if (!fullLessonPlayer || fullLessonPlayer.isStarted()) return;
    await fullLessonPlayer.playNow();
  }

  async function stopPlayback() {
    await fullLessonPlayer?.stopNow();
    playing = false;
  }

  // ---- Character drill ------------------------------------------------------

  /** Playback started from any trigger; the label flips to Replay afterwards. */
  function onDrillStart() {
    drillPlaying = true;
    drillPlayed = true;
  }

  async function playDrill() {
    if (!drillPlayer || drillPlayer.isStarted()) return;
    await drillPlayer.playNow();
  }

  async function stopDrill() {
    await drillPlayer?.stopNow();
    drillPlaying = false;
  }

  /** Another character is a new target: the old audio stops, the display follows. */
  function onDrillTargetChange(event: Event) {
    const target = (event.currentTarget as HTMLSelectElement).value;
    if (drillPlaying) void stopDrill();
    selectedLessonChar = target;
    drillPlayed = false;
  }

  /** The drill is an introduction: it hands over to the real copying exercise. */
  async function goToPassage() {
    mode = 'passage';
    // Focus follows the switch, so keyboard users land on the new mode.
    await tick();
    modePassageEl?.focus();
  }

  function onAnswerKeydown(event: KeyboardEvent) {
    // Enter checks the copy. Shift+Enter keeps the line-break behaviour for
    // anyone who formats their answer across lines. Space is deliberately left
    // alone here: in this field it types a space, and the start/replay shortcut
    // is the page-level one that runs while focus is outside a control.
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      if (inputText.trim() !== '') checkResult();
      return;
    }

    // Escape stops the transmission from inside the field as well, so a copy can
    // be cut short without leaving the box or reaching for the mouse.
    if (event.key === 'Escape' && playing) {
      event.preventDefault();
      void stopPlayback();
    }
  }

  // Session shortcuts, live while focus is outside a control: Space starts the
  // transmission, Escape stops it. The answer box settles its own keys (see
  // `onAnswerKeydown`), so typing is never intercepted — Space types a space
  // there, and Escape stops playback from inside the box too.
  $effect(() => {
    if (!browser) return;

    function onKeydown(event: KeyboardEvent) {
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        target.closest('input, textarea, select, button, summary, a')
      ) {
        return;
      }
      if (event.code === 'Space') {
        event.preventDefault();
        if (mode === 'drill') void playDrill();
        else void playSession();
      } else if (event.key === 'Escape') {
        if (mode === 'drill') {
          if (drillPlaying) void stopDrill();
        } else if (playing) {
          void stopPlayback();
        }
      }
    }

    document.addEventListener('keydown', onKeydown);
    return () => document.removeEventListener('keydown', onKeydown);
  });

  onDestroy(() => {
    if (autoSyncTimeout) clearTimeout(autoSyncTimeout);
    if (newExerciseTimer) clearTimeout(newExerciseTimer);
  });
</script>

<nav class="crumb-nav" aria-label={m.morse_title()}>
  <a class="crumb-link" href={href('/morse')}>
    <ArrowLeft size={14} aria-hidden="true" />
    {m.trainer_back_to_workshop()}
  </a>
</nav>

<header class="workspace-heading">
  <h1 class="page-title">{m.trainer_title()}</h1>
</header>

{#if showQuickStart}
  <section class="quickstart" aria-labelledby="quickstart-title">
    <details class="quickstart-guide" bind:open={quickStartInstructionsOpen}>
      <summary class="quickstart-summary">
        <ChevronRight size={16} aria-hidden="true" />
        <h2 id="quickstart-title" class="quickstart-title">{m.trainer_quickstart_title()}</h2>
      </summary>
      <ol class="quickstart-steps">
        <li>{m.trainer_quickstart_step1()}</li>
        <li>{m.trainer_quickstart_step2()}</li>
        <li>{m.trainer_quickstart_step3()}</li>
      </ol>
      <details class="quickstart-tips">
        <summary>{m.trainer_quickstart_tips()}</summary>
        <ul>
          <li>{m.trainer_quickstart_tip1()}</li>
          <li>{m.trainer_quickstart_tip2()}</li>
          <li>{m.trainer_quickstart_tip3()}</li>
        </ul>
      </details>
    </details>
    <button type="button" class="btn-ghost" onclick={dismissQuickStart}
      >{m.trainer_quickstart_start()}</button
    >
  </section>
{/if}

<div class="workspace">
  <!-- Side: what is being practised and how this visit is going. One panel:
       sections are separated by rules, not stacked cards. -->
  <aside class="workspace-side">
    <section class="panel side-panel" aria-labelledby="lesson-panel-title">
      <h2 id="lesson-panel-title" class="card-title">{m.trainer_label_lesson()}</h2>
      <div class="lesson-nav">
        <button
          type="button"
          class="btn-icon"
          onclick={prevLesson}
          disabled={chosenLesson <= 1}
          aria-label={m.trainer_lesson_prev()}
          title={m.trainer_lesson_prev()}
        >
          <ChevronLeft size={16} />
        </button>
        <select
          bind:value={chosenLesson}
          onchange={onLessonSelectChange}
          class="select lesson-select"
          aria-label={m.trainer_current_lesson()}
        >
          {#each LESSONS as lesson, index (index)}
            <option value={index + 1}>{index + 1} — {lesson.split('').join(', ')}</option>
          {/each}
        </select>
        <button
          type="button"
          class="btn-icon"
          onclick={nextLesson}
          disabled={chosenLesson >= LESSONS.length}
          aria-label={m.trainer_lesson_next()}
          title={m.trainer_lesson_next()}
        >
          <ChevronRight size={16} />
        </button>
      </div>

      <!-- Fixed-height set summary: one line per fact, so the card is the same
           height at every lesson. The full set appears on request only. -->
      <div class="lesson-summary">
        <p class="lesson-summary-learned">{learnedLabel}</p>
        <p class="lesson-summary-latest">
          {m.trainer_set_latest({ chars: latestChars.join(', ') })}
        </p>
      </div>

      <details class="charset" bind:this={charsetEl} bind:open={charsetOpen}>
        <summary class="charset-toggle">{m.trainer_view_set()}</summary>
        <div class="charset-popover">
          <p class="panel-label">{m.trainer_set_title()}</p>
          {#if letterChars.length > 0}
            <div class="charset-group">
              <span class="charset-group-label"
                >{m.trainer_set_letters()} · {letterChars.length}</span
              >
              <span class="charset-group-value">{letterChars.join(' ')}</span>
            </div>
          {/if}
          {#if numberChars.length > 0}
            <div class="charset-group">
              <span class="charset-group-label"
                >{m.trainer_set_numbers()} · {numberChars.length}</span
              >
              <span class="charset-group-value">{numberChars.join(' ')}</span>
            </div>
          {/if}
          {#if symbolChars.length > 0}
            <div class="charset-group">
              <span class="charset-group-label"
                >{m.trainer_set_symbols()} · {symbolChars.length}</span
              >
              <span class="charset-group-value">{symbolChars.join(' ')}</span>
            </div>
          {/if}
          <p class="charset-latest">{m.trainer_set_latest({ chars: latestChars.join(' ') })}</p>
        </div>
      </details>

      <hr class="side-divider" />

      <!-- Only the passage produces results, so the drill keeps this section
           out of the way unless there is something to see from a copy. -->
      {#if mode === 'passage' || attemptCount > 0}
        <h3 class="panel-label">{m.trainer_session_title()}</h3>
        {#if attemptCount === 0}
          <p class="side-note">{m.trainer_session_empty()}</p>
        {:else}
          <div class="session-metrics">
            <div class="metric">
              <span class="metric-label">{m.trainer_metric_attempts()}</span>
              <span class="metric-value">{attemptCount}</span>
            </div>
            <div class="metric">
              <span class="metric-label">{m.trainer_metric_best()}</span>
              <span class="metric-value">{percentage(bestAttempt)}</span>
            </div>
            <div class="metric">
              <span class="metric-label">{m.trainer_metric_average()}</span>
              <span class="metric-value">{percentage(averageAttempt)}</span>
            </div>
          </div>
        {/if}
      {/if}
      {#if !$user}
        <GuestNotice class="side-note" />
      {/if}
      <a class="session-link" href={href('/profile')}>{m.trainer_session_link()}</a>
    </section>
  </aside>

  <div class="workspace-main">
    <section class="panel console">
      <!-- Compact header: lesson and settings only. The character set lives in
           the lesson card, never as raw metadata here. -->
      <div class="console-head">
        <p class="console-title">
          {m.trainer_lesson_summary({
            lesson: String(chosenLesson),
            kind: lessonKindLabel
          })}
        </p>
        <p class="console-meta">
          {#if mode === 'passage'}
            {m.trainer_summary_meta({
              count: String(currentLessonChars.length),
              speed: `${charWpm}/${effWpm}`,
              hz: String(freq),
              time: formatClock(sendSeconds)
            })}
          {:else}
            {m.trainer_summary_meta_drill({
              count: String(currentLessonChars.length),
              speed: `${charWpm}/${effWpm}`,
              hz: String(freq)
            })}
          {/if}
        </p>
      </div>

      <!-- Mode switch: exactly one practice is on screen at a time. The drill
           leads, because the newest character is practised by ear first. -->
      <fieldset class="segmented">
        <legend class="sr-only">{m.trainer_mode_legend()}</legend>
        <label class="mode-option">
          <input type="radio" name="practice-mode" value="drill" bind:group={mode} />
          <span class="segmented-item">{m.trainer_mode_drill()}</span>
        </label>
        <label class="mode-option">
          <input
            type="radio"
            name="practice-mode"
            value="passage"
            bind:this={modePassageEl}
            bind:group={mode}
          />
          <span class="segmented-item">{m.trainer_mode_passage()}</span>
        </label>
      </fieldset>

      {#if mode === 'passage'}
        <ol class="flow" aria-label={m.trainer_flow_legend()}>
          {#each flowSteps as step, index (step.index)}
            <li
              class="flow-step"
              class:is-current={index === flowIndex}
              class:is-done={index < flowIndex}
              aria-current={index === flowIndex ? 'step' : undefined}
            >
              <span class="sr-only">{m.trainer_flow_step({ step: String(index + 1) })}:</span>
              <span class="flow-dot" aria-hidden="true"></span>{step.label()}
            </li>
          {/each}
        </ol>

        <MorsePlayer
          bind:this={fullLessonPlayer}
          text={lessonText}
          {charWpm}
          {effWpm}
          {freq}
          {volume}
          {startDelay}
          showSettings
          playTone={sessionStarted && !playing ? 'quiet' : 'primary'}
          showTransportExtras={playing}
          onStart={onSessionStart}
          onSettingsInput={onCwSettingInput}
          onEnded={() => (playing = false)}
          playLabel={sessionStarted ? m.trainer_replay() : m.player_play()}
          label={m.player_label()}
        />

        <div class="answer-block">
          <!-- The passage belongs to the review: it appears once the copy has
               been checked, and never during copy practice. -->
          {#if result >= 0}
            <div class="transcript">
              <p class="transcript-head">
                <span class="panel-label">{m.trainer_source_label()}</span>
              </p>
              <p class="quote-text">{lessonText}</p>
            </div>
          {/if}

          <label class="field answer-field">
            <span class="label-text">{m.trainer_answer_label()}</span>
            <textarea
              bind:this={answerEl}
              placeholder={m.trainer_answer_placeholder()}
              bind:value={inputText}
              oninput={onAnswerInput}
              onkeydown={onAnswerKeydown}
              autocapitalize="characters"
              autocomplete="off"
              autocorrect="off"
              spellcheck="false"
              disabled={!sessionStarted}
              class="textarea learn-answer-textarea"
              class:is-active={sessionStarted}></textarea>
          </label>

          <p class="session-state" aria-live="polite">{sessionStateText}</p>

          {#if !showOverlay && result >= 0}
            <p class="result-line" aria-live="polite">
              {m.trainer_result_last({ percent: percentage(result) })}
              <button
                type="button"
                class="quiet-btn quiet-btn--accent"
                onclick={() => (showOverlay = true)}>{m.trainer_result_review()}</button
              >
            </p>
          {/if}

          <p class="key-hints">
            {#if !sessionStarted}
              <span class="key-hint"><kbd>Space</kbd> {m.trainer_hint_start()}</span>
            {:else if !playing}
              <span class="key-hint"><kbd>Space</kbd> {m.trainer_hint_play()}</span>
            {/if}
            <span class="key-hint"><kbd>Enter</kbd> {m.trainer_hint_check()}</span>
            <span class="key-hint"><kbd>Esc</kbd> {m.trainer_hint_stop()}</span>
          </p>

          <div class="console-actions">
            <button
              class={isCheckPrimary ? 'btn-primary console-check' : 'btn-ghost console-check'}
              onclick={checkResult}
              disabled={inputText.trim() === ''}>{m.trainer_check()}</button
            >
            <button
              class="btn-ghost console-new"
              class:is-armed={newExerciseArmed}
              onclick={requestNewExercise}>{newExerciseLabel}</button
            >
          </div>
        </div>
      {:else}
        <div class="drill">
          <p class="panel-label">{m.trainer_drill_label()}</p>

          <!-- Familiarisation: the selected character is the reference, so it
               stays on screen. Playback always plays it, and the selector
               changes it. -->
          <p class="drill-char">
            <span class="drill-char-value">{selectedLessonChar}</span>
            {#if drillMorse}
              <span class="drill-morse"
                ><span class="sr-only">{m.trainer_drill_morse()}: </span>{drillMorse}</span
              >
            {/if}
          </p>

          <!-- Secondary action: practise another character from this lesson. -->
          <label class="field drill-picker-field">
            <span class="label-text">{m.trainer_choose_letter()}</span>
            <select
              class="select drill-picker"
              value={selectedLessonChar}
              onchange={onDrillTargetChange}
            >
              {#each currentLessonChars as char (char)}
                <option value={char}>{char}</option>
              {/each}
            </select>
          </label>

          <MorsePlayer
            bind:this={drillPlayer}
            text={Array(5).fill(selectedLessonChar).join('')}
            {charWpm}
            {effWpm}
            {freq}
            {volume}
            {startDelay}
            showSettings
            showTransportExtras={false}
            onStart={onDrillStart}
            onSettingsInput={onCwSettingInput}
            onEnded={() => (drillPlaying = false)}
            playTone={drillPlayed && !drillPlaying ? 'quiet' : 'primary'}
            playLabel={drillPlayed ? m.trainer_replay() : m.trainer_drill_play()}
            label={m.trainer_drill_audio()}
          />

          <p class="drill-focus">{m.trainer_drill_focus()}</p>

          <!-- The way into the real copying exercise. It is never a gate: the
               mode switch above works at any time, and once the character has
               been played this is the advised next step. -->
          <div class="drill-actions">
            <button class={drillPlayed ? 'btn-primary' : 'btn-ghost'} onclick={goToPassage}
              >{m.trainer_drill_cta()}</button
            >
          </div>
        </div>
      {/if}
    </section>
  </div>
</div>

{#if showOverlay}
  <ResultOverlay
    {result}
    {diffTokens}
    lessonNum={chosenLesson}
    sourceText={lessonText}
    {hasNextLesson}
    {hasPrevLesson}
    nextLessonNum={chosenLesson + 1}
    prevLessonNum={chosenLesson - 1}
    onClose={() => (showOverlay = false)}
    onNext={nextLesson}
    onPrev={prevLesson}
    onRegenerate={regenerate}
  />
{/if}

<style>
  .workspace-heading {
    margin-bottom: var(--block-gap);
  }

  /* Workspace: side rail for what is being practised, console for the practice
     itself. One column until there is room for both. */
  .workspace {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    min-width: 0;
  }

  .workspace-side,
  .workspace-main {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    min-width: 0;
  }

  /* The rail is secondary by construction: no surface, no border — the practice
     panel is the only raised card in the workspace. */
  .side-panel {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    background-color: transparent;
    border: none;
    border-radius: 0;
    padding: 0;
  }

  .side-panel :global(.card-title) {
    margin: 0;
  }

  .side-divider {
    width: 100%;
    border: none;
    border-top: 1px solid var(--border);
    margin: 0;
  }

  .console {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  /* Header: lesson + settings summary over a hairline — instrument chrome. */
  .console-head {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    padding-bottom: var(--space-3);
    border-bottom: 1px solid var(--border);
  }

  .console-title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--text-primary);
  }

  .console-meta {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-variant-numeric: tabular-nums;
    color: var(--text-muted);
  }

  /* Mode switch: native radios dressed by the shared segmented control — the
     checked one turns amber, so the current mode reads without a filled
     control. */
  .mode-option input {
    position: absolute;
    width: 1px;
    height: 1px;
    opacity: 0;
  }

  /* Flow: the five steps, current one in amber text (never a filled control). */
  .flow {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem var(--space-3);
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  /* Progress dots, not controls: filled = done, filled amber = current, ringed
     = still to come. The labels stay plain text so nothing looks clickable. */
  .flow-step {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .flow-step.is-done {
    color: var(--text-secondary);
  }

  .flow-step.is-current {
    color: var(--accent);
    font-weight: 600;
  }

  .flow-dot {
    flex-shrink: 0;
    width: 6px;
    height: 6px;
    border: 1px solid var(--border-control);
    border-radius: 50%;
  }

  .flow-step.is-done .flow-dot {
    background: var(--text-muted);
    border-color: var(--text-muted);
  }

  .flow-step.is-current .flow-dot {
    background: var(--accent);
    border-color: var(--accent);
  }

  .console-actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .console-check {
    flex: 1 1 12rem;
  }

  /* Armed state of the two-step New exercise control. */
  .console-new.is-armed {
    border-color: color-mix(in srgb, var(--danger) 55%, var(--border-control));
    color: var(--danger);
  }

  .answer-field {
    gap: var(--space-2);
  }

  .learn-answer-textarea {
    min-height: 4.5rem;
    font-size: var(--text-base);
    letter-spacing: 0.08em;
    line-height: 1.5;
  }

  /* The box grows with the exercise: small until there is something to type. */
  .learn-answer-textarea.is-active {
    min-height: 10rem;
  }

  /* Before the session starts the box is visibly a later step, not a broken one. */
  .learn-answer-textarea:disabled {
    background-color: var(--bg-inset);
    color: var(--text-muted);
    cursor: not-allowed;
  }

  /* Session state: the one line that says what to do next. */
  .session-state {
    margin: 0;
    min-height: 1.35rem;
    font-size: var(--text-sm);
    color: var(--text-secondary);
  }

  /* Shortcuts are reference material: the quietest text on the panel. */
  .key-hints {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2) var(--space-4);
    margin: 0;
    font-size: 0.6875rem;
    color: var(--text-muted);
  }

  .key-hint {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .key-hints kbd {
    font-family: var(--font-mono);
    font-size: 0.6875rem;
    padding: 0.05rem 0.3rem;
    border: 1px solid var(--border-control);
    border-bottom-width: 2px;
    border-radius: var(--radius-xs);
    color: var(--text-secondary);
    background: var(--bg-inset);
  }

  /* Only rendered when there is a result to report: the card ends at its
     action row, not at an empty placeholder. */
  .result-line {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--text-secondary);
  }

  .answer-block {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    min-width: 0;
  }

  .transcript {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .transcript-head {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0.35rem var(--space-3);
    margin: 0;
  }

  .lesson-nav {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: var(--space-2);
  }

  .lesson-select {
    min-width: 0;
  }

  /* Quiet inline actions (review, character set): the text does the work, and
     amber belongs to the next action, so these stay secondary until hovered. */
  .quiet-btn,
  .charset-toggle {
    background: none;
    border: none;
    padding: 0;
    font: inherit;
    font-size: var(--text-sm);
    color: var(--text-secondary);
    text-decoration: underline;
    text-underline-offset: 2px;
    cursor: pointer;
  }

  .quiet-btn:hover,
  .charset-toggle:hover {
    color: var(--accent);
  }

  /* The one quiet action that is the next step carries the amber. */
  .quiet-btn--accent {
    color: var(--accent);
  }

  /* Fixed-height set summary: the lesson card does not grow as the set does. */
  .lesson-summary {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .lesson-summary-learned {
    margin: 0;
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--text-primary);
  }

  .lesson-summary-latest {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--text-muted);
    overflow-wrap: anywhere;
  }

  /* The full character set opens on request, absolutely positioned so the
     trainer layout never moves. */
  .charset {
    position: relative;
  }

  .charset-toggle::-webkit-details-marker {
    display: none;
  }

  .charset-popover {
    position: absolute;
    left: 0;
    top: calc(100% + 0.4rem);
    z-index: 30;
    width: min(17rem, calc(100vw - 2rem));
    max-height: min(20rem, 60vh);
    overflow-y: auto;
    padding: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--bg-surface);
    box-shadow: var(--shadow-menu);
  }

  .charset-group {
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
  }

  .charset-group-label {
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  .charset-group-value {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    line-height: 1.6;
    color: var(--text-primary);
    overflow-wrap: anywhere;
  }

  .charset-latest {
    margin: 0;
    font-size: var(--text-xs);
    color: var(--text-secondary);
  }

  .side-note {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--text-muted);
  }

  /* Panels never let their contents spill into a neighbouring column. */
  .side-panel,
  .console {
    min-width: 0;
  }

  .session-metrics {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--space-3);
  }

  .session-link {
    align-self: flex-start;
    /* Grows the link to a full-size target without moving it in the sidebar. */
    padding: 0.3rem;
    margin: -0.3rem;
    font-size: var(--text-sm);
    color: var(--text-secondary);
    text-decoration: none;
  }

  .session-link:hover {
    color: var(--accent);
    text-decoration: underline;
  }

  /* Onboarding strip: inline and dismissible, never a modal over practice. */
  .quickstart {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--space-3) var(--space-4);
    padding: var(--space-4) var(--space-5);
    margin-bottom: var(--block-gap);
    border: 1px solid var(--border-card);
    border-left: 3px solid var(--accent);
    border-radius: var(--radius-md);
    background: var(--bg-surface);
  }

  .quickstart-guide {
    flex: 1 1 18rem;
    min-width: 0;
  }

  .quickstart-summary {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    list-style: none;
    cursor: pointer;
  }

  .quickstart-summary::marker {
    content: '';
  }

  .quickstart-summary::-webkit-details-marker {
    display: none;
  }

  .quickstart-summary :global(svg) {
    flex-shrink: 0;
    color: var(--accent);
  }

  .quickstart-guide[open] .quickstart-summary :global(svg) {
    transform: rotate(90deg);
  }

  .quickstart-title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--text-primary);
  }

  /* Preflight removes list markers; the numbered steps and the tips carry the
     structure, so their markers are restored here. */
  .quickstart-steps {
    margin: var(--space-2) 0 0;
    padding-left: 1.15rem;
    list-style: decimal;
    font-size: var(--text-sm);
    color: var(--text-secondary);
  }

  .quickstart-steps li + li,
  .quickstart-tips li + li {
    margin-top: 0.3rem;
  }

  .quickstart-tips {
    margin-top: var(--space-2);
    font-size: var(--text-sm);
    color: var(--text-secondary);
  }

  .quickstart-tips summary {
    cursor: pointer;
    color: var(--accent);
  }

  .quickstart-tips ul {
    margin: var(--space-2) 0 0;
    padding-left: 1.15rem;
    list-style: disc;
  }

  /* Drill: one character, one player, one way onward. */
  .drill {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    min-width: 0;
  }

  /* Compact selector: this lesson's characters, nothing else. */
  .drill-picker-field {
    max-width: 12rem;
    gap: var(--space-2);
  }

  .drill-picker {
    min-width: 0;
  }

  .drill-actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  /* The character being practised: big, always visible, with its pattern. */
  .drill-char {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: var(--space-4);
    margin: 0;
  }

  .drill-char-value {
    font-family: var(--font-mono);
    font-size: 2.75rem;
    line-height: 1;
    color: var(--text-primary);
  }

  .drill-morse {
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    letter-spacing: 0.18em;
    color: var(--text-secondary);
  }

  .drill-focus {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--text-muted);
  }

  /* The console gets the width it needs before the rail appears. */
  @media (min-width: 900px) {
    .workspace {
      display: grid;
      grid-template-columns: 17rem minmax(0, 1fr);
      align-items: start;
    }

    .workspace-side {
      position: sticky;
      top: 4.5rem;
    }
  }

  @media (max-width: 639px) {
    .quickstart {
      align-items: center;
      padding: var(--space-3);
      gap: var(--space-2);
    }

    .quickstart-summary {
      min-height: 2.75rem;
      padding-block: var(--space-2);
    }

    .charset-toggle {
      display: inline-flex;
      align-items: center;
      min-height: 2.75rem;
      padding-inline: var(--space-2);
    }

    /* Phones: the two passage actions stack instead of wrapping a full-width
       button beside a narrow one. One width for both, primary first, and no
       flex growth (the base `flex-basis` would stretch a stacked button). */
    .console-actions {
      flex-direction: column;
      align-items: stretch;
      gap: var(--space-2);
    }

    .console-actions > button {
      flex: 0 0 auto;
      width: 100%;
    }

    .learn-answer-textarea {
      min-height: 4rem;
    }

    .learn-answer-textarea.is-active {
      min-height: 8rem;
    }

    .drill-char-value {
      font-size: 2.25rem;
    }
  }
</style>
