import { describe, expect, it } from 'vitest';
import { calculateStreak, evaluateMilestones } from './motivation';

describe('Motivation & Forgiving Streak', () => {
  it('returns zeroes when no training has occurred', () => {
    const streak = calculateStreak([], '2026-10-04');
    expect(streak.currentStreakDays).toBe(0);
    expect(streak.longestStreakDays).toBe(0);
    expect(streak.totalActiveDays).toBe(0);
    expect(streak.isDailyGoalMet).toBe(false);
  });

  it('keeps streak alive if practised yesterday even if not yet trained today', () => {
    const dates = ['2026-10-01', '2026-10-02', '2026-10-03'];
    const streak = calculateStreak(dates, '2026-10-04', 1, 0);

    expect(streak.currentStreakDays).toBe(3);
    expect(streak.longestStreakDays).toBe(3);
    expect(streak.totalActiveDays).toBe(3);
    expect(streak.isDailyGoalMet).toBe(false);
  });

  it('increments streak and marks goal met when trained today', () => {
    const dates = ['2026-10-01', '2026-10-02', '2026-10-03'];
    const streak = calculateStreak(dates, '2026-10-04', 1, 1);

    expect(streak.currentStreakDays).toBe(4);
    expect(streak.longestStreakDays).toBe(4);
    expect(streak.totalActiveDays).toBe(4);
    expect(streak.isDailyGoalMet).toBe(true);
  });

  it('preserves longest streak and lifetime active days after a break', () => {
    // 5-day streak in September, break, then 1 day in October
    const dates = [
      '2026-09-10',
      '2026-09-11',
      '2026-09-12',
      '2026-09-13',
      '2026-09-14',
      '2026-10-04'
    ];
    const streak = calculateStreak(dates, '2026-10-04', 1, 1);

    expect(streak.currentStreakDays).toBe(1);
    expect(streak.longestStreakDays).toBe(5);
    expect(streak.totalActiveDays).toBe(6);
  });

  it('evaluates milestones idempotently based on stable character thresholds', () => {
    // 2 stable characters unlocks 'first_stable_pair'
    const m1 = evaluateMilestones(2, []);
    expect(m1).toEqual(['first_stable_pair']);

    // Re-evaluating with already unlocked does not duplicate
    const m2 = evaluateMilestones(2, ['first_stable_pair']);
    expect(m2).toEqual([]);

    // Advancing to 5 stable characters unlocks 'first_five_characters'
    const m3 = evaluateMilestones(5, ['first_stable_pair']);
    expect(m3).toEqual(['first_five_characters']);
  });
});
