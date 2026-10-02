import { describe, expect, it } from 'vitest';
import { calculateDuration, getFarnsworthWpmSet, buildAudioPlan } from './timing';

describe('buildAudioPlan', () => {
  it('produces one tone event per dot/dash with correct offsets', () => {
    const plan = buildAudioPlan('I', { charWpm: 20, effWpm: 10 });
    expect(plan.events).toEqual([
      { start: 0, duration: 0.06 },
      { start: 0.12, duration: 0.06 }
    ]);
    expect(plan.totalDuration).toBeCloseTo(0.18, 12);
  });

  it('spaces dashes and symbols with Farnsworth timings', () => {
    const plan = buildAudioPlan('M', { charWpm: 20, effWpm: 10 });
    // M = -- : dash (0.18) + symbol gap (0.06) + dash (0.18)
    expect(plan.events).toEqual([
      { start: 0, duration: 0.18 },
      { start: 0.24, duration: 0.18 }
    ]);
    expect(plan.totalDuration).toBeCloseTo(0.42, 12);
  });

  it('uses letter and word gaps for multi-character text', () => {
    const plan = buildAudioPlan('E E', { charWpm: 20, effWpm: 10 });
    const { charDot, letterSpace, wordSpace } = getFarnsworthWpmSet(20, 10);
    expect(plan.events[0]).toEqual({ start: 0, duration: charDot });
    expect(plan.events[1]).toEqual({ start: charDot + letterSpace + wordSpace, duration: charDot });
    expect(plan.totalDuration).toBeCloseTo(charDot + letterSpace + wordSpace + charDot, 12);
  });

  it('agrees with calculateDuration for every text shape', () => {
    for (const text of ['', 'E', 'K M', 'KMRU KMRU', 'E E', 'E!E', '5NN']) {
      const plan = buildAudioPlan(text, { charWpm: 20, effWpm: 10 });
      expect(plan.totalDuration).toBeCloseTo(calculateDuration(text, 20, 10), 12);
    }
  });

  it('ends at the last tone end for texts that do not end in a gap', () => {
    const plan = buildAudioPlan('KMR', { charWpm: 25, effWpm: 12 });
    const last = plan.events[plan.events.length - 1];
    expect(last.start + last.duration).toBeCloseTo(plan.totalDuration, 12);
  });

  it('carries playback settings through the plan', () => {
    const plan = buildAudioPlan('E', {
      charWpm: 20,
      effWpm: 10,
      frequency: 700,
      volume: 0.4,
      startDelay: 1.5
    });
    expect(plan.frequency).toBe(700);
    expect(plan.volume).toBe(0.4);
    expect(plan.startDelay).toBe(1.5);
    // fade = min(charDot * 0.1, 0.005)
    expect(plan.fade).toBeCloseTo(0.005, 12);
    expect(plan.text).toBe('E');
  });

  it('handles empty text with no events and zero duration', () => {
    const plan = buildAudioPlan('', { charWpm: 20, effWpm: 10 });
    expect(plan.events).toEqual([]);
    expect(plan.totalDuration).toBe(0);
  });

  it('keeps a zero start delay by default', () => {
    const plan = buildAudioPlan('E', { charWpm: 20, effWpm: 10 });
    expect(plan.startDelay).toBe(0);
    expect(plan.frequency).toBe(600);
    expect(plan.volume).toBe(1);
  });
});
