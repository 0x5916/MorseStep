<script lang="ts">
  import { ArrowRight } from '@lucide/svelte';
  import { localizedHref as href } from '$lib/i18n.svelte';
  import { LESSONS } from '$lib/morse';
  import { GITHUB_URL } from '$lib/seo';
  import * as m from '$lib/paraglide/messages';

  // The lists store the message functions, not their values, so the template
  // always reads the current locale (the layout also remounts on a switch).
  const steps = [
    { title: m.home_step1_title, body: m.home_step1_body },
    { title: m.home_step2_title, body: m.home_step2_body },
    { title: m.home_step3_title, body: m.home_step3_body }
  ];

  // Where to go next: the four surfaces of the product as one plain list.
  const destinations = [
    { path: '/morse/learn', title: m.nav_train, body: m.home_go_train },
    { path: '/forum', title: m.nav_forum, body: m.home_go_forum },
    { path: '/profile', title: m.nav_progress, body: m.home_go_progress },
    { path: '/about', title: m.nav_about, body: m.home_go_about }
  ];

  // Decorative trainer mock-up: show the character set a learner has unlocked.
  const PREVIEW_LESSON = 7;
  const previewChars = LESSONS.slice(0, PREVIEW_LESSON).join('').split('');
  const previewNewChars = (LESSONS[PREVIEW_LESSON - 1] ?? '').length;
</script>

<!-- Masthead: the product in one paragraph, with one action to take. -->
<section class="masthead">
  <h1 class="masthead-title">{m.home_hero_title()}</h1>
  <p class="masthead-lede">{m.home_hero_subtitle()}</p>
  <div class="masthead-actions">
    <a href={href('/morse/learn')} class="btn-cta"
      >{m.home_cta()}<ArrowRight size={18} aria-hidden="true" /></a
    >
    <a href={href('/about')} class="link">{m.home_hero_cta_secondary()}</a>
  </div>
</section>

<!-- What a session looks like, next to how the method works. -->
<section class="workbench">
  <div class="preview-col">
    <!-- Decorative: the interactive trainer lives on /morse/learn -->
    <div class="preview-frame" aria-hidden="true">
      <span class="card-label">{m.trainer_label_lesson()} {PREVIEW_LESSON}</span>
      <p class="preview-chars">
        {#each previewChars as char, index (char)}<span
            class="preview-char"
            class:is-new={index >= previewChars.length - previewNewChars}>{char}</span
          >{/each}
      </p>
      <span class="preview-line"></span>
      <div class="preview-answer">
        <span class="preview-answer-text">{m.trainer_answer_placeholder()}</span>
        <span class="preview-check">{m.trainer_check()}</span>
      </div>
    </div>
    <p class="body-text preview-caption">{m.home_preview_caption()}</p>
  </div>

  <div class="method">
    <h2 class="section-title">{m.home_steps_title()}</h2>
    <ol class="step-list">
      {#each steps as step, index (step.title)}
        <li class="step">
          <span class="step-number">{index + 1}</span>
          <div>
            <strong class="step-title">{step.title()}</strong>
            <p class="body-text">{step.body()}</p>
          </div>
        </li>
      {/each}
    </ol>
  </div>
</section>

<!-- Destinations: a plain list of where the product continues. -->
<section class="destinations">
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
  /* Masthead: left-aligned editorial opener. The headline is ink; the amber is
     reserved for the action next to it. */
  .masthead {
    padding-bottom: var(--section-gap);
  }

  /* The page's own title carries no rule: the sticky chrome already bounds it
     from above, and the lede below belongs to it rather than following it. */
  .masthead-title {
    margin: 0;
    max-width: 30rem;
    font-size: var(--text-3xl);
    line-height: var(--leading-tight);
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--text-primary);
  }

  /* The rule used to hold the lede off the heading; the gap does that now. */
  .masthead-lede {
    margin: var(--space-4) 0 var(--space-5);
    max-width: 38rem;
    font-size: var(--text-lg);
    line-height: var(--leading-relaxed);
    color: var(--text-secondary);
  }

  .masthead-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-4);
  }

  .workbench {
    display: grid;
    gap: var(--space-8);
    margin-top: var(--section-gap);
  }

  @media (min-width: 800px) {
    .workbench {
      grid-template-columns: minmax(0, 22rem) minmax(0, 1fr);
      align-items: start;
    }
  }

  .preview-col {
    min-width: 0;
  }

  /* Decorative mock of the trainer: it shows what a session looks like without
     pretending to be one. */
  .preview-frame {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    padding: var(--space-4);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--bg-inset);
  }

  .preview-frame :global(.card-label) {
    margin-bottom: 0;
  }

  .preview-chars {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    color: var(--text-secondary);
  }

  .preview-char {
    min-width: 1.6rem;
    padding: 0.15rem 0.3rem;
    text-align: center;
    border: 1px solid var(--border);
    border-radius: var(--radius-xs);
    background-color: var(--bg-surface);
  }

  .preview-char.is-new {
    border-color: color-mix(in srgb, var(--accent) 55%, var(--border));
    color: var(--accent);
    font-weight: 600;
  }

  /* The timing line: the playhead motif that identifies the trainer. */
  .preview-line {
    height: 2px;
    background: linear-gradient(to right, var(--accent) 0 38%, var(--border) 38% 100%);
  }

  .preview-answer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background-color: var(--bg-surface);
  }

  .preview-answer-text {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--text-muted);
    font-size: var(--text-sm);
  }

  /* Inside the mock the "check" affordance is a mono label, never a filled
     button: the frame is aria-hidden decoration. */
  .preview-check {
    flex-shrink: 0;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  .preview-caption {
    margin: var(--space-3) 0 0;
  }

  .method {
    min-width: 0;
  }

  .destinations {
    margin-top: var(--section-gap);
  }

  .dest-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
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
    margin-top: var(--section-gap);
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
</style>
