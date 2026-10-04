<script lang="ts">
  import { tick } from 'svelte';
  import type { InputMode } from '../../training/v2/types';

  interface Props {
    disabled?: boolean;
    expectedLength?: number;
    autoFocus?: boolean;
    onSubmit: (text: string, mode: InputMode) => void;
  }

  let {
    disabled = false,
    expectedLength = 1,
    autoFocus = true,
    onSubmit = () => {}
  }: Props = $props();

  let inputVal = $state('');
  let inputEl = $state<HTMLInputElement | null>(null);

  $effect(() => {
    if (!disabled && autoFocus && inputEl) {
      tick().then(() => inputEl?.focus());
    }
  });

  function handleInput(event: Event) {
    const target = event.target as HTMLInputElement;
    const clean = target.value.trim().toUpperCase();
    inputVal = clean;

    // Auto-submit when expected single character or group length is reached
    if (clean.length === expectedLength) {
      submit(clean, 'keyboard');
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (disabled) return;

    if (event.key === 'Enter') {
      event.preventDefault();
      if (inputVal.length > 0) {
        submit(inputVal, 'keyboard');
      }
    }
  }

  function submit(text: string, mode: InputMode) {
    if (disabled || text.trim() === '') return;
    const finalVal = text.trim().toUpperCase();
    inputVal = '';
    onSubmit(finalVal, mode);
  }
</script>

<div class="answer-input-container">
  <input
    bind:this={inputEl}
    type="text"
    class="answer-field"
    value={inputVal}
    {disabled}
    maxlength={expectedLength}
    autocomplete="off"
    autocapitalize="characters"
    spellcheck="false"
    placeholder="·"
    aria-label="Type your answer"
    oninput={handleInput}
    onkeydown={handleKeydown}
  />
  <div class="input-instruction">
    <span>Type the character or press <kbd class="kbd">Enter</kbd> to submit</span>
  </div>
</div>

<style>
  .answer-input-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
  }

  .answer-field {
    width: 5.5rem;
    height: 5.5rem;
    background-color: var(--bg-surface);
    border: 2px solid var(--border-control);
    border-radius: var(--radius-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 3rem;
    font-weight: 700;
    text-align: center;
    text-transform: uppercase;
    transition: border-color var(--transition-fast);
  }

  .answer-field:focus {
    border-color: var(--learning-current, var(--accent));
    outline: none;
    box-shadow: var(--focus-ring);
  }

  .answer-field:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .input-instruction {
    font-size: var(--text-xs);
    color: var(--text-muted);
  }

  .kbd {
    display: inline-block;
    padding: 0.1rem 0.35rem;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    background-color: var(--bg-inset);
    border: 1px solid var(--border);
    border-radius: var(--radius-xs);
    color: var(--text-secondary);
  }
</style>
