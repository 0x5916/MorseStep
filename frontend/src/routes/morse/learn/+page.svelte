<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { SvelteMap } from 'svelte/reactivity';
  import { localizedHref } from '$lib/i18n.svelte';
  import { LESSONS } from '$lib/training/sequence';
  import { openTrainingDb } from '$lib/data/training-db';
  import { createSessionRepository } from '$lib/data/session-repository';
  import { createAttemptRepository } from '$lib/data/attempt-repository';
  import { migrateLegacyLocalStorage } from '$lib/data/legacy-migration';
  import { reduceCharacterMastery } from '$lib/training/v2/mastery';
  import type { CharacterMastery, TrainingSessionRecord } from '$lib/training/v2/types';
  import LearnHero, { type HeroStateKind } from '$lib/components/learning/LearnHero.svelte';
  import CoursePath from '$lib/components/learning/CoursePath.svelte';
  import GuestNotice from '$lib/components/GuestNotice.svelte';
  import { user } from '$lib/auth';
  import { Dumbbell } from '@lucide/svelte';
  import * as m from '$lib/paraglide/messages';

  let loading = $state(true);
  let errorMsg = $state('');
  let currentStep = $state(1);
  let suggestedStep = $state<number | undefined>(undefined);
  let inProgressSession = $state<TrainingSessionRecord | null>(null);
  let masteryMap = $state<Map<string, CharacterMastery>>(new Map());
  let reviewChars = $state<string[]>([]);
  let hasAttempts = $state(false);

  let heroKind = $derived.by<HeroStateKind>(() => {
    if (loading) return 'loading';
    if (errorMsg) return 'error';
    if (inProgressSession) return 'resume';
    if (reviewChars.length > 0) return 'review-due';
    if (currentStep >= LESSONS.length) return 'complete';
    if (currentStep === 1 && !hasAttempts) return 'new';
    return 'next';
  });

  let currentIntroduced = $derived(LESSONS[currentStep - 1] ?? 'KM');

  onMount(async () => {
    try {
      const db = await openTrainingDb();

      // 1. Run safe legacy local storage migration if not already done
      const migration = await migrateLegacyLocalStorage(db);
      if (migration.suggestedStep > 1) {
        suggestedStep = migration.suggestedStep;
      }

      const sessionRepo = createSessionRepository(db);
      const attemptRepo = createAttemptRepository(db);

      // 2. Check for active/interrupted session
      inProgressSession = await sessionRepo.getLatestInProgressSession();

      // 3. Query historical attempts to derive character masteries
      const recentAttempts = await attemptRepo.getAttemptsByTimeRange(
        new Date(Date.now() - 60 * 86400000).toISOString(),
        new Date().toISOString()
      );
      hasAttempts = recentAttempts.length > 0;

      const map = new SvelteMap<string, CharacterMastery>();
      const needReview: string[] = [];

      let maxUnlocked = 1;

      for (let s = 1; s <= LESSONS.length; s++) {
        const chars = LESSONS[s - 1].split('');
        let allStable = true;

        for (const ch of chars) {
          const charMastery = reduceCharacterMastery(ch, recentAttempts);
          map.set(ch, charMastery);

          if (charMastery.status === 'review') {
            needReview.push(ch);
          }
          if (charMastery.status !== 'stable') {
            allStable = false;
          }
        }

        if (allStable && s < LESSONS.length) {
          maxUnlocked = s + 1;
        } else if (!allStable) {
          break;
        }
      }

      currentStep = maxUnlocked;
      masteryMap = map;
      reviewChars = needReview;
      loading = false;
    } catch (err) {
      console.error('Failed to load Learn home data:', err);
      errorMsg = err instanceof Error ? err.message : 'Storage initialization failed';
      loading = false;
    }
  });

  function handleStartLesson(step: number) {
    void goto(localizedHref(`/morse/learn/session?step=${step}`));
  }

  function handleResumeSession() {
    const s = inProgressSession?.step ?? currentStep;
    void goto(localizedHref(`/morse/learn/session?step=${s}`));
  }

  function handleDiscardResume() {
    inProgressSession = null;
  }
</script>

<svelte:head>
  <title>{m.nav_learn()} · MorseStep</title>
</svelte:head>

<div class="page-narrow">
  <div class="learn-home-container">
    <header class="learn-header">
      <h1 class="page-title">{m.learn_title()}</h1>
      <p class="learn-subtitle">{m.learn_subtitle()}</p>
    </header>

    <LearnHero
      kind={heroKind}
      step={currentStep}
      introducedChar={currentIntroduced}
      {reviewChars}
      resumableSessionId={inProgressSession?.id}
      errorMessage={errorMsg}
      onStart={handleStartLesson}
      onResume={handleResumeSession}
      onDiscardResume={handleDiscardResume}
    />

    {#if !$user}
      <GuestNotice class="body-text" />
    {/if}

    <section class="path-section" aria-labelledby="path-heading">
      <div class="section-header-row">
        <h2 id="path-heading" class="section-title">{m.learn_path_title()}</h2>
        {#if !loading && !errorMsg}
          <span class="path-meta">
            {m.learn_path_unlocked({ count: currentStep, total: LESSONS.length })}
          </span>
        {/if}
      </div>
      <p class="path-hint">{m.learn_path_hint()}</p>

      {#if !loading && !errorMsg}
        <CoursePath {currentStep} {masteryMap} {suggestedStep} onSelectStep={handleStartLesson} />
      {/if}
    </section>

    <div class="practice-hub-cta">
      <p class="practice-cta-text">{m.learn_practice_hint()}</p>
      <a href={localizedHref('/morse/practice')} class="btn-ghost practice-link">
        <Dumbbell size={16} aria-hidden="true" />
        <span>{m.learn_practice_cta()}</span>
      </a>
    </div>
  </div>
</div>

<style>
  .learn-home-container {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: var(--space-6);
    width: 100%;
    margin: 0 auto;
  }

  .learn-header {
    text-align: left;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-2);
  }

  .page-title {
    margin: 0;
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--text-primary);
  }

  .learn-subtitle {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--text-secondary);
    max-width: 28rem;
    line-height: var(--leading-normal);
  }

  .path-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    width: 100%;
    max-width: var(--max-width-narrow, 46rem);
  }

  .section-header-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .section-title {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--text-primary);
  }

  .path-meta {
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  .path-hint {
    margin: 0;
    font-size: var(--text-sm);
    line-height: var(--leading-normal);
    color: var(--text-secondary);
  }

  .practice-hub-cta {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: center;
    gap: var(--space-3);
    padding-top: var(--space-4);
    border-top: 1px solid var(--border);
    text-align: left;
  }

  .practice-cta-text {
    margin: 0;
    max-width: 27rem;
    font-size: var(--text-sm);
    color: var(--text-muted);
  }

  .practice-link {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    min-height: var(--answer-target-min);
  }
</style>
