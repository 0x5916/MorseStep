<script lang="ts">
  import { onMount } from 'svelte';
  import {
    ArrowRight,
    ChevronRight,
    Dumbbell,
    Info,
    LayoutDashboard,
    MessageSquare,
    Play,
    Square
  } from '@lucide/svelte';
  import { createWebAudioEngine, type AudioEngine } from '$lib/audio/engine';
  import { buildAudioPlan } from '$lib/training/timing';
  import { localizedHref as href } from '$lib/i18n.svelte';
  import { getLessonCharacterSet } from '$lib/training/sequence';
  import { GITHUB_URL } from '$lib/seo';
  import * as m from '$lib/paraglide/messages';

  // The lists store the message functions, not their values, so the template
  // always reads the current locale (the layout also remounts on a switch).
  const steps = [
    { title: m.home_step1_title, body: m.home_step1_body },
    { title: m.home_step2_title, body: m.home_step2_body },
    { title: m.home_step3_title, body: m.home_step3_body }
  ];

  const destinations = [
    { path: '/morse/practice', title: m.nav_practice, body: m.home_go_practice, icon: Dumbbell },
    {
      path: '/morse/progress',
      title: m.nav_progress,
      body: m.home_go_progress,
      icon: LayoutDashboard
    },
    { path: '/forum', title: m.nav_forum, body: m.home_go_forum, icon: MessageSquare },
    { path: '/about', title: m.nav_about, body: m.home_go_about, icon: Info }
  ];

  const PREVIEW_LESSON = 1;
  const previewChars = getLessonCharacterSet(PREVIEW_LESSON);
  let sampleCharacter = $state<string | null>(null);
  let sampleError = $state(false);
  let audio: AudioEngine | null = null;

  onMount(() => {
    audio = createWebAudioEngine();
    const unsubscribe = audio.subscribe(() => {
      if (!audio?.isActive()) sampleCharacter = null;
    });
    return () => {
      unsubscribe();
      void audio?.dispose();
      audio = null;
    };
  });

  function playSample(character: string) {
    if (!audio) return;
    sampleError = false;
    if (sampleCharacter === character) {
      sampleCharacter = null;
      void audio.stop({ notify: false });
      return;
    }
    try {
      audio.play(buildAudioPlan(character, { charWpm: 20, effWpm: 20, volume: 0.2 }));
      sampleCharacter = character;
    } catch {
      sampleCharacter = null;
      sampleError = true;
      void audio.stop({ notify: false });
    }
  }

  function stopHiddenSample() {
    if (document.hidden) {
      sampleCharacter = null;
      void audio?.stop({ notify: false });
    }
  }
</script>

<svelte:document onvisibilitychange={stopHiddenSample} />

<section class="masthead" aria-labelledby="home-title">
  <div class="masthead-artwork" aria-hidden="true">
    <img
      class="key-artwork"
      src="/images/home/telegraph-key.webp"
      alt=""
      width="960"
      height="640"
      fetchpriority="high"
      decoding="async"
    />
    <img
      class="antenna-artwork"
      src="/images/home/antenna.webp"
      alt=""
      width="600"
      height="400"
      loading="lazy"
      decoding="async"
    />
    <img
      class="station-artwork"
      src="/images/home/radio-station.webp"
      alt=""
      width="800"
      height="533"
      loading="lazy"
      decoding="async"
    />
  </div>
  <div class="masthead-copy">
    <h1 id="home-title" class="masthead-title">{m.home_hero_title()}</h1>
    <p class="masthead-lede">{m.home_hero_subtitle()}</p>
    <div class="masthead-actions">
      <a href={href('/morse/learn')} class="btn-cta"
        >{m.home_cta()}<ArrowRight size={18} aria-hidden="true" /></a
      >
      <a href={href('/morse/practice')} class="link practice-link">{m.home_hero_cta_secondary()}</a>
    </div>
    <p class="body-text reassurance">{m.home_reassurance()}</p>
  </div>
</section>

<div class="learning-intro">
  <!-- This is a sound introduction, not an assessed recognition prompt. -->
  <figure class="preview-frame" aria-labelledby="home-preview-title">
    <div class="preview-heading">
      <h2 id="home-preview-title" class="preview-title">{m.home_preview_title()}</h2>
      <span class="preview-lesson">{m.learn_path_lesson({ step: PREVIEW_LESSON })}</span>
    </div>
    <div class="preview-chars">
      {#each previewChars as char (char)}
        <button
          type="button"
          class="preview-char"
          aria-label={sampleCharacter === char
            ? m.home_sample_stop({ character: char })
            : m.home_sample_play({ character: char })}
          aria-pressed={sampleCharacter === char}
          onclick={() => playSample(char)}
        >
          <span class="sample-letter">{char}</span>
          <span class="sample-action">
            {#if sampleCharacter === char}<Square size={16} aria-hidden="true" />{:else}<Play
                size={16}
                aria-hidden="true"
              />{/if}
            {sampleCharacter === char ? m.player_stop() : m.home_step1_title()}
          </span>
        </button>
      {/each}
    </div>
    <p class="sample-status body-text" aria-live="polite" aria-atomic="true">
      {sampleCharacter
        ? m.home_sample_playing({ character: sampleCharacter })
        : m.home_sample_hint()}
    </p>
    {#if sampleError}<p class="sample-error body-text" role="alert">{m.home_sample_error()}</p>{/if}
    <figcaption class="preview-caption">
      <p class="body-text">{m.home_preview_caption()}</p>
      <a href={href('/morse/learn')} class="link preview-link"
        >{m.home_cta()}<ArrowRight size={16} aria-hidden="true" /></a
      >
    </figcaption>
  </figure>

  <section class="method" aria-labelledby="home-method-title">
    <h2 id="home-method-title" class="section-title">{m.home_steps_title()}</h2>
    <ol class="step-list">
      {#each steps as step, index (step.title)}
        <li class="step">
          <span class="step-number" aria-hidden="true">{index + 1}</span>
          <div>
            <strong class="step-title">{step.title()}</strong>
            <p class="body-text">{step.body()}</p>
          </div>
        </li>
      {/each}
    </ol>
  </section>
</div>

<!-- Destinations: a plain list of where the product continues. -->
<section class="destinations" aria-labelledby="home-destinations-title">
  <div class="destinations-copy">
    <h2 id="home-destinations-title" class="section-title">{m.home_go_title()}</h2>
    <ul class="row-list">
      {#each destinations as destination (destination.path)}
        <li>
          <a class="row-link dest-row" href={href(destination.path)}>
            <span class="dest-icon"><destination.icon size={22} aria-hidden="true" /></span>
            <span class="dest-copy">
              <span class="dest-title">{destination.title()}</span>
              <span class="dest-body">{destination.body()}</span>
            </span>
            <ChevronRight size={18} class="dest-chevron" aria-hidden="true" />
          </a>
        </li>
      {/each}
    </ul>
  </div>
</section>

<!-- Who builds it. -->
<section class="colophon">
  <p class="body-text">{m.home_author_line()}</p>
  <div class="colophon-links">
    <a href={href('/about')} class="link">{m.home_author_link()}</a>
    <a href={GITHUB_URL} class="link" rel="noopener noreferrer" target="_blank"
      >{m.home_author_github()}</a
    >
  </div>
</section>

<style>
  .learning-intro,
  .destinations,
  .colophon {
    --home-section-gap: calc(var(--space-6) * 2);
  }

  .masthead {
    position: relative;
    isolation: isolate;
    display: grid;
    justify-items: center;
    gap: var(--space-6);
  }

  .masthead-copy {
    min-width: 0;
    max-width: 34rem;
    text-align: center;
  }

  .masthead-artwork {
    grid-row: 2;
    width: 100%;
    pointer-events: none;
  }

  .key-artwork,
  .antenna-artwork,
  .station-artwork {
    display: block;
    height: auto;
    object-fit: contain;
  }

  .key-artwork {
    width: 12rem;
    margin-inline: auto;
  }

  .antenna-artwork,
  .station-artwork {
    display: none;
  }

  .masthead-title {
    margin: 0 auto;
    max-width: 14ch;
    font-size: clamp(var(--text-3xl), 5.5vw, 4.5rem);
    line-height: var(--leading-tight);
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--text-primary);
    text-wrap: balance;
  }

  .masthead-lede {
    margin: var(--space-4) 0 var(--space-5);
    font-size: var(--text-lg);
    line-height: var(--leading-relaxed);
    color: var(--text-secondary);
    text-wrap: pretty;
  }

  .masthead-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: center;
    gap: var(--space-4);
  }

  .masthead-actions :global(a) {
    min-height: var(--answer-target-min);
  }

  .practice-link {
    display: inline-flex;
    align-items: center;
  }

  .reassurance {
    margin: var(--space-3) 0 0;
  }

  .learning-intro {
    display: grid;
    align-items: start;
    gap: var(--space-8);
    margin-top: var(--home-section-gap);
  }

  .preview-frame {
    display: flex;
    flex-direction: column;
    min-width: 0;
    gap: var(--space-4);
    margin: 0;
    padding: var(--space-6);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--bg-inset);
  }

  .preview-heading {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: var(--space-2);
  }

  .preview-title {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: 600;
    line-height: var(--leading-snug);
  }

  .preview-lesson {
    color: var(--text-secondary);
    font-size: var(--text-sm);
  }

  .preview-chars {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
    margin: 0;
    color: var(--text-primary);
  }

  .preview-char {
    display: flex;
    flex: 1;
    flex-direction: column;
    align-items: center;
    gap: var(--space-2);
    min-width: var(--answer-target-min);
    padding: var(--space-4) var(--space-3);
    text-align: center;
    border: 1px solid var(--border-control);
    border-radius: var(--radius-xs);
    background-color: var(--bg-surface);
    cursor: pointer;
  }

  .preview-char:hover,
  .preview-char[aria-pressed='true'] {
    border-color: var(--accent);
    background-color: var(--bg-inset);
  }

  .sample-letter {
    font-family: var(--font-mono);
    font-size: var(--text-3xl);
    line-height: var(--leading-tight);
  }

  .sample-action,
  .preview-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
  }

  .sample-status {
    min-height: calc(2em * var(--leading-normal));
    margin: 0;
  }

  .sample-error {
    margin: 0;
    color: var(--status-bad);
  }

  .preview-link {
    justify-content: space-between;
    min-height: var(--answer-target-min);
    padding-top: var(--space-3);
    border-top: 1px solid var(--border);
  }

  .preview-caption {
    display: grid;
    gap: var(--space-4);
  }

  .preview-caption .body-text {
    margin: 0;
  }

  .method {
    min-width: 0;
  }

  .section-title {
    margin-bottom: var(--space-6);
    padding: 0;
    border: 0;
    font-size: var(--text-2xl);
    text-wrap: balance;
  }

  .method .step-list {
    display: grid;
    gap: var(--space-6);
  }

  .step .body-text {
    margin: var(--space-1) 0 0;
    max-width: 48ch;
    font-size: var(--text-base);
  }

  .destinations {
    margin-top: var(--home-section-gap);
  }

  .destinations-copy {
    min-width: 0;
  }

  .destinations li {
    display: grid;
  }

  .dest-row {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: var(--space-4);
    min-height: 7rem;
    padding: var(--space-5) var(--space-3);
    border-bottom: 1px solid var(--border);
  }

  .dest-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--answer-target-min);
    height: var(--answer-target-min);
    border-radius: var(--radius-md);
    background-color: var(--bg-inset);
    color: var(--accent);
  }

  .dest-copy {
    display: grid;
    gap: var(--space-1);
  }

  .dest-row :global(.dest-chevron) {
    color: var(--text-muted);
  }

  .dest-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--text-primary);
  }

  .dest-body {
    max-width: 32rem;
    font-size: var(--text-sm);
    color: var(--text-muted);
  }

  .colophon {
    margin-top: var(--home-section-gap);
    padding-top: var(--space-8);
    border-top: 1px solid var(--border);
  }

  .colophon :global(.body-text) {
    margin: 0;
    max-width: 60ch;
    font-size: var(--text-base);
  }

  .colophon-links {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-4);
    margin-top: var(--space-2);
  }

  .colophon-links :global(a) {
    display: inline-flex;
    align-items: center;
    min-height: var(--answer-target-min);
  }

  @media (max-width: 479px) {
    .masthead-actions {
      flex-direction: column;
      align-items: stretch;
      gap: var(--space-2);
    }

    .practice-link {
      justify-content: center;
    }
  }

  @media (min-width: 800px) {
    .learning-intro,
    .destinations,
    .colophon {
      --home-section-gap: calc(var(--space-8) * 2);
    }

    .learning-intro {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr);
      gap: calc(var(--space-6) * 2);
    }

    .destinations .row-list {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      column-gap: var(--space-8);
    }
  }

  @media (min-width: 1100px) {
    .masthead {
      min-height: clamp(32rem, 68svh, 40rem);
      align-items: center;
    }

    .masthead-artwork {
      position: absolute;
      grid-row: auto;
      inset-block: 0;
      left: 50%;
      z-index: -1;
      width: 100vw;
      overflow: clip;
      transform: translateX(-50%);
      background:
        radial-gradient(
          ellipse at 10% 20%,
          color-mix(in srgb, var(--bg-inset) 80%, transparent),
          transparent 45%
        ),
        radial-gradient(
          ellipse at 90% 80%,
          color-mix(in srgb, var(--bg-inset) 80%, transparent),
          transparent 45%
        );
    }

    .key-artwork,
    .antenna-artwork,
    .station-artwork {
      position: absolute;
      display: block;
      margin: 0;
    }

    .key-artwork {
      top: var(--space-8);
      left: calc(var(--space-10) * -2);
      width: clamp(18rem, 25vw, 28rem);
      transform: rotate(-12deg);
    }

    .antenna-artwork {
      top: var(--space-6);
      right: calc(var(--space-8) * 2);
      width: clamp(12rem, 18vw, 20rem);
      transform: rotate(8deg);
    }

    .station-artwork {
      right: calc(var(--space-6) * -2);
      bottom: calc(var(--space-6) * -1);
      width: clamp(18rem, 24vw, 26rem);
      transform: rotate(-6deg);
    }
  }
</style>
