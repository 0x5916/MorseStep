<script lang="ts">
  import { LESSONS } from '../../training/sequence';
  import CoursePathItem, { type PathItemStatus } from './CoursePathItem.svelte';
  import type { CharacterMastery } from '../../training/v2/types';

  interface Props {
    currentStep: number;
    masteryMap?: Map<string, CharacterMastery>;
    suggestedStep?: number;
    onSelectStep: (step: number) => void;
  }

  let {
    currentStep = 1,
    masteryMap = new Map(),
    suggestedStep,
    onSelectStep = () => {}
  }: Props = $props();

  function getItemStatus(step: number, chars: string): PathItemStatus {
    if (step > currentStep) {
      if (suggestedStep && step <= suggestedStep) {
        return 'legacy-unverified';
      }
      return 'locked';
    }

    if (step === currentStep) {
      return 'current';
    }

    // Check if any character introduced at this step is due for review
    const charList = chars.split('');
    const anyReviewDue = charList.some((c) => masteryMap.get(c)?.status === 'review');
    if (anyReviewDue) return 'review';

    const allStable = charList.every((c) => masteryMap.get(c)?.status === 'stable');
    if (allStable) return 'stable';

    return 'available';
  }
</script>

<div class="course-path" role="list" aria-label="Course path">
  {#each LESSONS as chars, idx (idx + 1)}
    {@const stepNum = idx + 1}
    {@const status = getItemStatus(stepNum, chars)}
    <CoursePathItem
      step={stepNum}
      characters={chars}
      {status}
      isCurrent={stepNum === currentStep}
      onSelect={() => onSelectStep(stepNum)}
    />
  {/each}
</div>

<style>
  .course-path {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    width: 100%;
    max-width: var(--max-width-narrow, 46rem);
  }
</style>
