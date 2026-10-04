<script lang="ts">
  import type { Snippet } from 'svelte';
  import { ArrowLeft, Pause, Play } from '@lucide/svelte';
  import SessionProgress from './SessionProgress.svelte';
  import ExitSessionDialog from './ExitSessionDialog.svelte';

  interface Props {
    currentPromptIndex: number;
    totalPrompts: number;
    isPaused?: boolean;
    canPause?: boolean;
    onExit: () => void;
    onPauseToggle?: () => void;
    children?: Snippet;
  }

  let {
    currentPromptIndex = 0,
    totalPrompts = 1,
    isPaused = false,
    canPause = true,
    onExit = () => {},
    onPauseToggle = () => {},
    children
  }: Props = $props();

  let showExitConfirm = $state(false);

  function handleExitClick() {
    showExitConfirm = true;
  }

  function handleConfirmExit() {
    showExitConfirm = false;
    onExit();
  }

  function handleCancelExit() {
    showExitConfirm = false;
  }
</script>

<div class="session-shell">
  <header class="session-header">
    <button
      type="button"
      class="btn-icon"
      aria-label="Exit session"
      title="Exit session"
      onclick={handleExitClick}
    >
      <ArrowLeft size={18} />
    </button>

    <div class="session-progress-container">
      <SessionProgress
        current={Math.min(currentPromptIndex + 1, totalPrompts)}
        total={totalPrompts}
      />
    </div>

    {#if canPause}
      <button
        type="button"
        class="btn-icon"
        aria-label={isPaused ? 'Resume session' : 'Pause session'}
        title={isPaused ? 'Resume session' : 'Pause session'}
        onclick={onPauseToggle}
      >
        {#if isPaused}
          <Play size={18} />
        {:else}
          <Pause size={18} />
        {/if}
      </button>
    {:else}
      <div class="header-spacer"></div>
    {/if}
  </header>

  <main class="session-stage">
    <div class="session-content">
      {#if children}
        {@render children()}
      {/if}
    </div>
  </main>

  <ExitSessionDialog
    isOpen={showExitConfirm}
    onConfirm={handleConfirmExit}
    onCancel={handleCancelExit}
  />
</div>

<style>
  .session-shell {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
    min-height: 100dvh;
    background-color: var(--bg-base);
    color: var(--text-primary);
    overflow-x: hidden;
  }

  .session-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-top: calc(var(--space-3) + env(safe-area-inset-top, 0px));
    padding-right: calc(var(--space-4) + env(safe-area-inset-right, 0px));
    padding-bottom: var(--space-3);
    padding-left: calc(var(--space-4) + env(safe-area-inset-left, 0px));
    border-bottom: 1px solid var(--border);
    background-color: var(--bg-surface);
    position: sticky;
    top: 0;
    z-index: 50;
  }

  .session-progress-container {
    flex: 1;
    display: flex;
    justify-content: center;
    max-width: 14rem;
    margin: 0 var(--space-3);
  }

  .header-spacer {
    width: 2.25rem;
  }

  .session-stage {
    flex: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    padding-top: var(--space-4);
    padding-right: calc(var(--space-4) + env(safe-area-inset-right, 0px));
    padding-bottom: calc(var(--space-4) + env(safe-area-inset-bottom, 0px));
    padding-left: calc(var(--space-4) + env(safe-area-inset-left, 0px));
  }

  .session-content {
    width: 100%;
    max-width: var(--session-max-width, 42rem);
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    margin: auto 0;
  }

  @media (max-width: 480px) {
    .session-header {
      padding-top: calc(var(--space-2) + env(safe-area-inset-top, 0px));
      padding-right: calc(var(--space-3) + env(safe-area-inset-right, 0px));
      padding-bottom: var(--space-2);
      padding-left: calc(var(--space-3) + env(safe-area-inset-left, 0px));
    }
  }
</style>
