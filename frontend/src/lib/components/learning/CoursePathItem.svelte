<script lang="ts">
  import { CheckCircle2, CircleDot, AlertCircle, Lock, Circle } from '@lucide/svelte';

  export type PathItemStatus =
    'stable' | 'current' | 'review' | 'available' | 'locked' | 'legacy-unverified';

  interface Props {
    step: number;
    characters: string;
    status: PathItemStatus;
    isCurrent?: boolean;
    onSelect?: () => void;
  }

  let { step, characters, status, isCurrent = false, onSelect = () => {} }: Props = $props();

  let isInteractive = $derived(status !== 'locked');
  let statusLabel = $derived.by(() => {
    switch (status) {
      case 'stable':
        return 'Stable';
      case 'current':
        return 'Current';
      case 'review':
        return 'Review due';
      case 'available':
        return 'Ready';
      case 'locked':
        return 'Locked';
      case 'legacy-unverified':
        return 'Not measured yet';
    }
  });
</script>

{#if isInteractive}
  <button
    type="button"
    class="path-item is-interactive"
    class:is-current={isCurrent}
    onclick={onSelect}
    aria-label={`Lesson ${step}: ${characters}, ${statusLabel}`}
  >
    <div class="node-icon status-{status}">
      {#if status === 'stable'}
        <CheckCircle2 size={16} />
      {:else if status === 'current'}
        <CircleDot size={16} />
      {:else if status === 'review'}
        <AlertCircle size={16} />
      {:else}
        <Circle size={14} />
      {/if}
    </div>

    <div class="node-details">
      <div class="node-title">
        <span class="step-label">Lesson {step}</span>
        <span class="char-label">{characters}</span>
      </div>
      <span class="status-text status-text-{status}">{statusLabel}</span>
    </div>
  </button>
{:else}
  <div
    class="path-item is-locked"
    role="listitem"
    aria-label={`Lesson ${step}: ${characters}, ${statusLabel}`}
  >
    <div class="node-icon status-locked">
      <Lock size={14} />
    </div>

    <div class="node-details">
      <div class="node-title">
        <span class="step-label">Lesson {step}</span>
        <span class="char-label">{characters}</span>
      </div>
      <span class="status-text status-text-locked">{statusLabel}</span>
    </div>
  </div>
{/if}

<style>
  .path-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background-color: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    transition:
      background-color var(--transition-fast),
      border-color var(--transition-fast);
  }

  .is-interactive {
    cursor: pointer;
  }

  .is-interactive:hover {
    background-color: var(--bg-inset);
    border-color: var(--border-subtle);
  }

  .is-current {
    border-color: var(--learning-current, var(--accent));
    box-shadow: inset 2px 0 0 var(--learning-current, var(--accent));
  }

  .is-locked {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .node-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2rem;
    height: 2rem;
    border-radius: var(--radius-xs);
    background-color: var(--bg-inset);
    flex-shrink: 0;
  }

  .status-stable {
    color: var(--learning-stable, var(--status-good));
  }

  .status-current {
    color: var(--learning-current, var(--accent));
  }

  .status-review {
    color: var(--learning-review, var(--status-ok));
  }

  .status-locked {
    color: var(--text-muted);
  }

  .status-available,
  .status-legacy-unverified {
    color: var(--text-secondary);
  }

  .node-details {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    min-width: 0;
  }

  .node-title {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .step-label {
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  .char-label {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--text-primary);
  }

  .status-text {
    font-size: var(--text-xs);
  }

  .status-text-stable {
    color: var(--learning-stable, var(--status-good));
  }

  .status-text-current {
    color: var(--learning-current, var(--accent));
    font-weight: 600;
  }

  .status-text-review {
    color: var(--learning-review, var(--status-ok));
  }

  .status-text-locked,
  .status-text-legacy-unverified {
    color: var(--text-muted);
  }
</style>
