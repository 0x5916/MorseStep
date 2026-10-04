import { describe, expect, it } from 'vitest';
import { reduceCharacterMastery } from './mastery';
import type { AttemptEvent } from './types';

function createMockAttempt(overrides: Partial<AttemptEvent> = {}): AttemptEvent {
  return {
    schemaVersion: 1,
    id: 'att_1',
    sessionId: 'sess_1',
    promptId: 'prm_1',
    promptKind: 'recall',
    targetCharacter: 'T',
    enteredText: 'T',
    isCorrect: true,
    classification: 'automatic',
    latencyMs: 1200,
    replayCount: 0,
    inputMode: 'keyboard',
    charWpm: 20,
    effWpm: 12,
    freqHz: 600,
    createdAt: '2026-10-04T12:00:00.000Z',
    ...overrides
  };
}

describe('Character Mastery Reducer', () => {
  it('returns new status when no attempts exist for the symbol', () => {
    const mastery = reduceCharacterMastery('T', []);
    expect(mastery.status).toBe('new');
    expect(mastery.totalAttempts).toBe(0);
    expect(mastery.sessionCount).toBe(0);
    expect(mastery.lastPractisedAt).toBeNull();
  });

  it('never marks a symbol stable from a single attempt', () => {
    const attempt = createMockAttempt();
    const mastery = reduceCharacterMastery('T', [attempt]);

    expect(mastery.status).toBe('learning');
    expect(mastery.totalAttempts).toBe(1);
    expect(mastery.sessionCount).toBe(1);
    expect(mastery.rollingAccuracy).toBe(1);
  });

  it('strictly enforces the multi-session stability rule (cannot be stable from 1 session)', () => {
    // 20 perfect attempts, all within sess_1
    const attempts: AttemptEvent[] = Array.from({ length: 20 }, (_, i) =>
      createMockAttempt({
        id: `att_${i}`,
        sessionId: 'sess_1',
        latencyMs: 1100,
        createdAt: new Date(1700000000000 + i * 10000).toISOString()
      })
    );

    const mastery = reduceCharacterMastery('T', attempts);
    expect(mastery.totalAttempts).toBe(20);
    expect(mastery.sessionCount).toBe(1);
    // Despite 20/20 correct and fast, single-session cannot be stable:
    expect(mastery.status).toBe('learning');
  });

  it('marks a character stable when multi-session, accuracy, count, and speed gates pass', () => {
    // 8 attempts in session 1, 8 attempts in session 2
    const attempts: AttemptEvent[] = [];
    for (let i = 0; i < 8; i++) {
      attempts.push(
        createMockAttempt({
          id: `s1_${i}`,
          sessionId: 'sess_1',
          latencyMs: 1200,
          createdAt: '2026-10-01T10:00:00.000Z'
        })
      );
    }
    for (let i = 0; i < 8; i++) {
      attempts.push(
        createMockAttempt({
          id: `s2_${i}`,
          sessionId: 'sess_2',
          latencyMs: 1250,
          createdAt: '2026-10-02T10:00:00.000Z'
        })
      );
    }

    const mastery = reduceCharacterMastery('T', attempts, {
      nowIso: '2026-10-02T12:00:00.000Z' // within 3-day review interval
    });

    expect(mastery.totalAttempts).toBe(16);
    expect(mastery.sessionCount).toBe(2);
    expect(mastery.rollingAccuracy).toBe(1);
    expect(mastery.medianLatencyMs).toBeLessThanOrEqual(1500);
    expect(mastery.status).toBe('stable');
  });

  it('transitions to review status when reviewIntervalDays expires', () => {
    // Multi-session stable set, last practiced on 2026-10-01
    const attempts: AttemptEvent[] = [
      ...Array.from({ length: 7 }, (_, i) =>
        createMockAttempt({
          id: `s1_${i}`,
          sessionId: 'sess_1',
          createdAt: '2026-10-01T10:00:00.000Z'
        })
      ),
      ...Array.from({ length: 7 }, (_, i) =>
        createMockAttempt({
          id: `s2_${i}`,
          sessionId: 'sess_2',
          createdAt: '2026-10-02T10:00:00.000Z'
        })
      )
    ];

    // Evaluate 5 days later (> 3 days review interval)
    const mastery = reduceCharacterMastery('T', attempts, {
      nowIso: '2026-10-07T10:00:00.000Z'
    });

    expect(mastery.status).toBe('review');
  });

  it('does not grant stability to slow-correct answers even if accuracy is 100%', () => {
    // 16 attempts across 2 sessions, all correct but slow (2800ms > 1500ms)
    const attempts: AttemptEvent[] = [
      ...Array.from({ length: 8 }, (_, i) =>
        createMockAttempt({
          id: `s1_${i}`,
          sessionId: 'sess_1',
          latencyMs: 2800,
          classification: 'developing',
          createdAt: '2026-10-01T10:00:00.000Z'
        })
      ),
      ...Array.from({ length: 8 }, (_, i) =>
        createMockAttempt({
          id: `s2_${i}`,
          sessionId: 'sess_2',
          latencyMs: 2900,
          classification: 'developing',
          createdAt: '2026-10-02T10:00:00.000Z'
        })
      )
    ];

    const mastery = reduceCharacterMastery('T', attempts, {
      nowIso: '2026-10-02T12:00:00.000Z'
    });

    expect(mastery.rollingAccuracy).toBe(1);
    expect(mastery.medianLatencyMs).toBe(2850);
    // Because medianLatency exceeds 1500ms, it remains learning:
    expect(mastery.status).toBe('learning');
  });
});
