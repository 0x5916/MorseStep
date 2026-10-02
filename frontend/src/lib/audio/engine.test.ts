import { describe, expect, it } from 'vitest';
import type { AudioEngine } from './engine';
import { createWebAudioEngine } from './engine';
import { buildAudioPlan } from '../training/timing';

type ParamCall = {
  method: 'setValueAtTime' | 'linearRampToValueAtTime';
  value: number;
  time: number;
};

class FakeParam {
  value = 0;
  calls: ParamCall[] = [];

  setValueAtTime(value: number, time: number): void {
    this.calls.push({ method: 'setValueAtTime', value, time });
  }

  linearRampToValueAtTime(value: number, time: number): void {
    this.calls.push({ method: 'linearRampToValueAtTime', value, time });
  }
}

class FakeGainNode {
  gain = new FakeParam();
  connected: unknown = null;

  connect(target: unknown): void {
    this.connected = target;
  }
}

class FakeOscillatorNode {
  frequency = new FakeParam();
  started = false;
  stoppedAt: number | null = null;
  onended: (() => void) | null = null;
  connected: unknown = null;

  connect(target: unknown): void {
    this.connected = target;
  }

  start(): void {
    this.started = true;
  }

  stop(time: number): void {
    this.stoppedAt = time;
  }
}

class FakeAudioContext {
  currentTime = 10;
  destination = { name: 'destination' };
  state = 'running';
  oscillators: FakeOscillatorNode[] = [];
  gains: FakeGainNode[] = [];
  closeCalls = 0;
  suspendCalls = 0;
  resumeCalls = 0;

  createOscillator(): FakeOscillatorNode {
    const osc = new FakeOscillatorNode();
    this.oscillators.push(osc);
    return osc;
  }

  createGain(): FakeGainNode {
    const gain = new FakeGainNode();
    this.gains.push(gain);
    return gain;
  }

  async close(): Promise<void> {
    this.closeCalls += 1;
    this.state = 'closed';
  }

  async suspend(): Promise<void> {
    this.suspendCalls += 1;
    this.state = 'suspended';
  }

  async resume(): Promise<void> {
    this.resumeCalls += 1;
    this.state = 'running';
  }
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function setup() {
  const contexts: FakeAudioContext[] = [];
  const createContext = () => {
    const context = new FakeAudioContext();
    contexts.push(context);
    return context as unknown as AudioContext;
  };
  const engine: AudioEngine = createWebAudioEngine({ createContext });
  return { contexts, createContext, engine };
}

const plan = buildAudioPlan('I', {
  charWpm: 20,
  effWpm: 10,
  frequency: 700,
  volume: 0.5,
  startDelay: 1
});

describe('WebAudioEngine', () => {
  it('creates the audio context only when play is called', () => {
    let created = 0;
    const engine = createWebAudioEngine({
      createContext: () => {
        created += 1;
        return new FakeAudioContext() as unknown as AudioContext;
      }
    });

    expect(created).toBe(0);
    engine.play(plan);
    expect(created).toBe(1);
  });

  it('schedules the plan on the audio timeline with gain ramps', () => {
    const { contexts, engine } = setup();
    engine.play(plan);

    const context = contexts[0];
    const osc = context.oscillators[0];
    expect(osc.frequency.value).toBe(700);
    expect(osc.started).toBe(true);
    expect(osc.stoppedAt).toBeCloseTo(10 + 1 + plan.totalDuration, 12);

    const calls = context.gains[0].gain.calls;
    // One initial silence step plus four ramp steps per tone event. The first
    // event's leading silence step shares the initial step's time and value.
    expect(calls).toHaveLength(1 + plan.events.length * 4);
    expect(calls[0]).toEqual({ method: 'setValueAtTime', value: 0, time: 11 });
    expect(calls[1]).toEqual({ method: 'setValueAtTime', value: 0, time: 11 });
    expect(calls[2].method).toBe('linearRampToValueAtTime');
    expect(calls[2].value).toBe(0.5);
    expect(calls[2].time).toBeCloseTo(11.005, 12);
    expect(calls[3].method).toBe('setValueAtTime');
    expect(calls[3].value).toBe(0.5);
    expect(calls[3].time).toBeCloseTo(11.055, 12);
    expect(calls[4].method).toBe('linearRampToValueAtTime');
    expect(calls[4].value).toBe(0);
    expect(calls[4].time).toBeCloseTo(11.06, 12);
    // Second tone starts after the symbol gap.
    expect(calls[5].time).toBeCloseTo(11.12, 12);
  });

  it('notifies ended exactly once when the oscillator finishes naturally', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    engine.subscribe((event) => events.push(event));

    engine.play(plan);
    expect(engine.isActive()).toBe(true);
    contexts[0].oscillators[0].onended?.();
    await flush();

    expect(events).toEqual(['ended']);
    expect(engine.isActive()).toBe(false);
    expect(engine.elapsed()).toBe(0);
    expect(contexts[0].closeCalls).toBe(1);

    // A repeated callback from the same (stale) playback does nothing.
    contexts[0].oscillators[0].onended?.();
    await flush();
    expect(events).toEqual(['ended']);
  });

  it('ignores a stale completion from a playback replaced by a newer one', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    engine.subscribe((event) => events.push(event));

    engine.play(plan);
    const staleOsc = contexts[0].oscillators[0];
    engine.play(plan);

    expect(contexts).toHaveLength(2);
    expect(contexts[0].closeCalls).toBe(1);
    expect(engine.isActive()).toBe(true);

    staleOsc.onended?.();
    await flush();
    expect(events).toEqual([]);
    expect(engine.isActive()).toBe(true);

    contexts[1].oscillators[0].onended?.();
    await flush();
    expect(events).toEqual(['ended']);
    expect(engine.isActive()).toBe(false);
  });

  it('stops idempotently and notifies once', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    engine.subscribe((event) => events.push(event));

    engine.play(plan);
    await engine.stop();
    await engine.stop();

    expect(events).toEqual(['ended']);
    expect(engine.isActive()).toBe(false);
    expect(contexts[0].closeCalls).toBe(1);
  });

  it('supports a silent stop without notifying', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    engine.subscribe((event) => events.push(event));

    engine.play(plan);
    await engine.stop({ notify: false });

    expect(events).toEqual([]);
    expect(engine.isActive()).toBe(false);
    expect(contexts[0].closeCalls).toBe(1);
  });

  it('suspends and resumes the timeline, and is safe while idle', async () => {
    const { contexts, engine } = setup();

    await engine.pause();
    await engine.resume();
    expect(engine.isPaused()).toBe(false);

    engine.play(plan);
    await engine.pause();
    expect(engine.isPaused()).toBe(true);
    expect(contexts[0].suspendCalls).toBe(1);

    await engine.pause();
    expect(contexts[0].suspendCalls).toBe(1);

    await engine.resume();
    expect(engine.isPaused()).toBe(false);
    expect(contexts[0].resumeCalls).toBe(1);

    await engine.resume();
    expect(contexts[0].resumeCalls).toBe(1);
  });

  it('disposes silently, repeatedly, and blocks further playback', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    engine.subscribe((event) => events.push(event));

    engine.play(plan);
    await engine.dispose();

    expect(events).toEqual([]);
    expect(engine.isActive()).toBe(false);
    expect(contexts[0].closeCalls).toBe(1);

    await engine.dispose();
    engine.play(plan);
    expect(contexts).toHaveLength(1);
  });

  it('unsubscribes listeners and ignores subscriptions after disposal', async () => {
    const { contexts, engine } = setup();
    const events: string[] = [];
    const unsubscribe = engine.subscribe((event) => events.push(event));

    unsubscribe();
    engine.play(plan);
    contexts[0].oscillators[0].onended?.();
    await flush();
    expect(events).toEqual([]);

    await engine.dispose();
    const late = engine.subscribe((event) => events.push(event));
    late();
    expect(events).toEqual([]);
  });
});
