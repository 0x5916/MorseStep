/**
 * Motivation, Daily Goal, and Forgiving Streak Engine for MorseStep V2.
 *
 * Principles:
 * - Counts completed scored sessions, not passive app opens.
 * - Forgiving: missing a day never deletes mastery or blocks training access.
 * - Local calendar day resolution (`YYYY-MM-DD`) respecting learner timezone.
 * - Preserves longest streak and lifetime active days across breaks.
 * - Meaningful milestones celebrate authentic competency (stable character unlocks).
 */

export interface StreakState {
  currentStreakDays: number;
  longestStreakDays: number;
  totalActiveDays: number;
  lastActiveDate: string | null;
  isDailyGoalMet: boolean;
}

export type MilestoneType =
  | 'first_stable_pair'
  | 'first_five_characters'
  | 'ten_characters'
  | 'twenty_characters'
  | 'alphabet_completed';

export interface MilestoneDefinition {
  id: MilestoneType;
  title: string;
  description: string;
  requiredStableChars: number;
}

export const MILESTONES: MilestoneDefinition[] = [
  {
    id: 'first_stable_pair',
    title: 'First Sound Pair',
    description: 'Stabilized recognition of your first two Morse characters (K and M).',
    requiredStableChars: 2
  },
  {
    id: 'first_five_characters',
    title: 'High Five',
    description: 'Stabilized 5 distinct Morse symbols in memory.',
    requiredStableChars: 5
  },
  {
    id: 'ten_characters',
    title: 'Ten In Rhythm',
    description: 'Quarter of the standard Koch curriculum stabilized.',
    requiredStableChars: 10
  },
  {
    id: 'twenty_characters',
    title: 'Halfway Mark',
    description: 'Mastered 20 characters by sound recognition.',
    requiredStableChars: 20
  },
  {
    id: 'alphabet_completed',
    title: 'Full Alphabet',
    description: 'All 26 letters of the alphabet recognized automatically.',
    requiredStableChars: 26
  }
];

function diffInCalendarDays(dateA: string, dateB: string): number {
  const msA = Date.parse(`${dateA}T00:00:00Z`);
  const msB = Date.parse(`${dateB}T00:00:00Z`);
  return Math.round(Math.abs(msB - msA) / 86400000);
}

/**
 * Calculates streak metrics from an array of active `YYYY-MM-DD` date strings.
 */
export function calculateStreak(
  activeDates: string[],
  todayDate: string,
  targetSessionsToday = 1,
  completedSessionsToday = 0
): StreakState {
  if (activeDates.length === 0 && completedSessionsToday === 0) {
    return {
      currentStreakDays: 0,
      longestStreakDays: 0,
      totalActiveDays: 0,
      lastActiveDate: null,
      isDailyGoalMet: false
    };
  }

  // Deduplicate and sort dates ascending
  const uniqueDates = Array.from(new Set(activeDates)).sort();
  if (completedSessionsToday > 0 && !uniqueDates.includes(todayDate)) {
    uniqueDates.push(todayDate);
    uniqueDates.sort();
  }

  const totalActiveDays = uniqueDates.length;
  const lastActiveDate = uniqueDates[uniqueDates.length - 1] ?? null;

  // Calculate longest streak across entire history
  let longestStreak = 0;
  let runningStreak = 0;
  let prevDate: string | null = null;

  for (const date of uniqueDates) {
    if (!prevDate) {
      runningStreak = 1;
    } else {
      const diff = diffInCalendarDays(prevDate, date);
      if (diff === 1) {
        runningStreak += 1;
      } else {
        runningStreak = 1;
      }
    }
    if (runningStreak > longestStreak) {
      longestStreak = runningStreak;
    }
    prevDate = date;
  }

  // Calculate current streak relative to today
  let currentStreak = 0;
  if (lastActiveDate) {
    const daysSinceLast = diffInCalendarDays(lastActiveDate, todayDate);
    if (daysSinceLast === 0) {
      // Practised today: count backwards from today
      currentStreak = 1;
      let checkDate = lastActiveDate;
      for (let i = uniqueDates.length - 2; i >= 0; i--) {
        const d = uniqueDates[i];
        if (diffInCalendarDays(d, checkDate) === 1) {
          currentStreak += 1;
          checkDate = d;
        } else {
          break;
        }
      }
    } else if (daysSinceLast === 1) {
      // Practised yesterday: streak still alive
      currentStreak = 1;
      let checkDate = lastActiveDate;
      for (let i = uniqueDates.length - 2; i >= 0; i--) {
        const d = uniqueDates[i];
        if (diffInCalendarDays(d, checkDate) === 1) {
          currentStreak += 1;
          checkDate = d;
        } else {
          break;
        }
      }
    } else {
      // Streak broken, but longestStreak and totalActiveDays remain preserved
      currentStreak = 0;
    }
  }

  const isDailyGoalMet = completedSessionsToday >= targetSessionsToday;

  return {
    currentStreakDays: currentStreak,
    longestStreakDays: longestStreak,
    totalActiveDays,
    lastActiveDate,
    isDailyGoalMet
  };
}

/**
 * Evaluates newly achieved milestones based on stable character counts.
 */
export function evaluateMilestones(
  stableCharacterCount: number,
  alreadyUnlocked: MilestoneType[] = []
): MilestoneType[] {
  const newlyUnlocked: MilestoneType[] = [];
  const existingSet = new Set(alreadyUnlocked);

  for (const milestone of MILESTONES) {
    if (stableCharacterCount >= milestone.requiredStableChars && !existingSet.has(milestone.id)) {
      newlyUnlocked.push(milestone.id);
    }
  }

  return newlyUnlocked;
}
