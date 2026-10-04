<script lang="ts">
  interface Props {
    isOpen: boolean;
    onConfirm: () => void;
    onCancel: () => void;
  }

  let { isOpen = false, onConfirm = () => {}, onCancel = () => {} }: Props = $props();

  let dialogEl = $state<HTMLDivElement | null>(null);

  function handleKeydown(event: KeyboardEvent) {
    if (!isOpen) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      onCancel();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div
    class="dialog-backdrop"
    role="presentation"
    onclick={onCancel}
    onkeydown={(e) => e.key === 'Escape' && onCancel()}
  >
    <div
      class="dialog-card"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="dialog-title"
      aria-describedby="dialog-desc"
      tabindex="-1"
      bind:this={dialogEl}
      onclick={(e) => e.stopPropagation()}
      onkeydown={(e) => e.stopPropagation()}
    >
      <h2 id="dialog-title" class="section-title">Leave session?</h2>
      <p id="dialog-desc" class="dialog-text">
        Your completed attempts from this session are saved on this device. You can resume anytime.
      </p>

      <div class="dialog-actions">
        <button type="button" class="btn-primary" onclick={onCancel}> Resume practice </button>
        <button type="button" class="btn-ghost" onclick={onConfirm}> Exit </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .dialog-backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.65);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-4);
  }

  .dialog-card {
    background-color: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-overlay);
    padding: var(--space-6);
    max-width: 26rem;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .section-title {
    margin: 0;
    font-size: var(--text-lg);
    color: var(--text-primary);
  }

  .dialog-text {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--text-secondary);
    line-height: var(--leading-normal);
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
    margin-top: var(--space-2);
  }
</style>
