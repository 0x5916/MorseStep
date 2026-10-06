<script lang="ts">
  import { ArrowRight } from '@lucide/svelte';
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
    { path: '/morse/practice', title: m.nav_practice, body: m.home_go_practice },
    { path: '/morse/progress', title: m.nav_progress, body: m.home_go_progress },
    { path: '/forum', title: m.nav_forum, body: m.home_go_forum },
    { path: '/about', title: m.nav_about, body: m.home_go_about }
  ];

  const PREVIEW_LESSON = 1;
  const previewChars = getLessonCharacterSet(PREVIEW_LESSON);
</script>

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
  <!-- An introduction to the first lesson, with no pretend trainer controls. -->
  <figure class="preview-frame" aria-labelledby="home-preview-title">
    <div class="preview-heading">
      <h2 id="home-preview-title" class="preview-title">{m.home_preview_title()}</h2>
      <span class="preview-lesson">{m.learn_path_lesson({ step: PREVIEW_LESSON })}</span>
    </div>
    <p class="preview-chars">
      {#each previewChars as char (char)}<span class="preview-char">{char}</span>{/each}
    </p>
    <figcaption class="body-text preview-caption">{m.home_preview_caption()}</figcaption>
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
<section class="destinations">
  <div class="destinations-copy">
    <h2 class="section-title">{m.home_go_title()}</h2>
    <ul class="row-list">
      {#each destinations as destination (destination.path)}
        <li>
          <a class="row-link dest-row" href={href(destination.path)}>
            <span class="dest-title">{destination.title()}</span>
            <span class="dest-body">{destination.body()}</span>
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
    padding: var(--space-5);
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
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
    color: var(--text-primary);
  }

  .preview-char {
    min-width: var(--answer-target-min);
    padding: var(--space-2) var(--space-3);
    text-align: center;
    border: 1px solid var(--border);
    border-radius: var(--radius-xs);
    background-color: var(--bg-surface);
  }

  .preview-caption {
    margin: 0;
  }

  .method {
    min-width: 0;
  }

  .method .section-title {
    margin-top: 0;
  }

  .method .step-list {
    display: grid;
    gap: var(--space-6);
  }

  .destinations {
    margin-top: var(--home-section-gap);
  }

  .destinations-copy {
    min-width: 0;
  }

  .dest-row {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-2);
  }

  .dest-title {
    font-size: var(--text-base);
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
  }

  .colophon :global(.body-text) {
    margin: 0;
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

  @media (min-width: 800px) {
    .learning-intro,
    .destinations,
    .colophon {
      --home-section-gap: calc(var(--space-8) * 2);
    }

    .learning-intro {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr);
    }
  }

  @media (min-width: 1100px) {
    .masthead {
      min-height: 40rem;
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
