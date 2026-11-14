// The sounds of the journey replay. They are made in the browser with the Web Audio API (tones and filtered noise), so there is
// nothing to download and no sound file whose licence could matter. `cueFor` and `pickCues` are plain functions; `Sfx` is the
// part that needs a browser and is created only after a click (browsers do not allow sound before one).
import type { ChronicleEvent } from "./chronicle";

export type Cue =
  | "quest-accept" | "quest-done" | "level" | "kill" | "coin" | "item" | "item-rare" | "death" | "boss-kill" | "boss-wipe"
  | "pvp-win" | "pvp-loss" | "zone" | "flight" | "skill" | "group" | "instance";

/** The sound of a moment, or null when it stays silent (an abandoned quest, an emote). */
export function cueFor(e: ChronicleEvent): Cue | null {
  switch (e.k) {
    case "quest": return e.a === "accept" ? "quest-accept" : e.a === "turnin" ? "quest-done" : null;
    case "kill": return "kill";
    case "loot": return (e.q ?? 1) >= 3 ? "item-rare" : (e.q ?? 1) >= 2 ? "item" : null;
    case "money": return (e.n ?? 0) > 0 ? "coin" : null;
    case "level": return "level";
    case "skill": return "skill";
    case "death": return "death";
    case "zone": return "zone";
    case "travel": return "flight";
    case "dungeon": return e.a === "enter" ? "instance" : null;
    case "group": return "group";
    case "boss": return e.a === "wipe" ? "boss-wipe" : "boss-kill";
    case "pvp": return e.a === "win" ? "pvp-win" : "pvp-loss";
    default: return null;
  }
}
/** What matters most when several things happen at once. */
const PRIORITY: Record<Cue, number> = {
  "boss-kill": 10, "boss-wipe": 10, "pvp-win": 10, "pvp-loss": 10, level: 9, death: 8, "item-rare": 7, "quest-done": 6, "quest-accept": 5, instance: 5,
  flight: 4, zone: 4, group: 3, skill: 3, coin: 2, item: 2, kill: 1,
};
/** The sounds for the moments that passed since the last look: at most `max`, each kind once, the most important first. */
export function pickCues(events: readonly ChronicleEvent[], max = 3): Cue[] {
  const seen = new Set<Cue>();
  for (const e of events) { const cue = cueFor(e); if (cue) seen.add(cue); }
  return [...seen].sort((a, b) => PRIORITY[b] - PRIORITY[a]).slice(0, max);
}
/** Above this playback speed the sounds would only be noise. */
export const MAX_SOUND_SPEED = 60;

const NOTE = { C4: 261.63, D4: 293.66, E4: 329.63, G4: 392, A4: 440, B3: 246.94, C5: 523.25, D5: 587.33, E5: 659.25, G5: 784, A5: 880, C6: 1046.5, E6: 1318.5 };

type Voice = { freq: number; at: number; length: number; type?: OscillatorType; gain?: number; to?: number };

export class Sfx {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private noiseBuffer: AudioBuffer | null = null;
  private volume = 0.5;
  private last = new Map<Cue, number>();
  /** Create the audio context. Call it from a click or a key press. */
  unlock(): boolean {
    if (typeof window === "undefined") return false;
    if (!this.ctx) {
      const Context = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Context) return false;
      this.ctx = new Context();
      this.master = this.ctx.createGain();
      this.master.gain.value = this.volume * 0.6;
      this.master.connect(this.ctx.destination);
    }
    if (this.ctx.state === "suspended") void this.ctx.resume();
    return true;
  }
  setVolume(v: number) {
    this.volume = Math.min(1, Math.max(0, v));
    if (this.master && this.ctx) this.master.gain.setTargetAtTime(this.volume * 0.6, this.ctx.currentTime, 0.02);
  }
  get ready() { return this.ctx !== null; }
  close() { void this.ctx?.close(); this.ctx = null; this.master = null; }

  private tone({ freq, at, length, type = "sine", gain = 0.2, to }: Voice) {
    const ctx = this.ctx, master = this.master;
    if (!ctx || !master) return;
    const start = ctx.currentTime + at;
    const osc = ctx.createOscillator(), amp = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, start);
    if (to) osc.frequency.exponentialRampToValueAtTime(to, start + length);
    amp.gain.setValueAtTime(0.0001, start);
    amp.gain.exponentialRampToValueAtTime(gain, start + Math.min(0.015, length / 4));
    amp.gain.exponentialRampToValueAtTime(0.0001, start + length);
    osc.connect(amp); amp.connect(master);
    osc.start(start); osc.stop(start + length + 0.02);
  }
  /** A burst of noise through a filter: wind, a thud, a rumble. */
  private noise(at: number, length: number, from: number, to: number, gain: number, kind: BiquadFilterType = "bandpass") {
    const ctx = this.ctx, master = this.master;
    if (!ctx || !master) return;
    if (!this.noiseBuffer) {
      this.noiseBuffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const data = this.noiseBuffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    }
    const start = ctx.currentTime + at;
    const src = ctx.createBufferSource(), filter = ctx.createBiquadFilter(), amp = ctx.createGain();
    src.buffer = this.noiseBuffer; src.loop = true;
    filter.type = kind; filter.Q.value = 1.2;
    filter.frequency.setValueAtTime(from, start);
    filter.frequency.exponentialRampToValueAtTime(to, start + length);
    amp.gain.setValueAtTime(0.0001, start);
    amp.gain.exponentialRampToValueAtTime(gain, start + length * 0.25);
    amp.gain.exponentialRampToValueAtTime(0.0001, start + length);
    src.connect(filter); filter.connect(amp); amp.connect(master);
    src.start(start); src.stop(start + length + 0.05);
  }
  private run(notes: [number, number][], length: number, step: number, type: OscillatorType = "triangle", gain = 0.18) {
    notes.forEach(([freq], i) => this.tone({ freq, at: i * step, length, type, gain }));
  }

  play(cue: Cue) {
    if (!this.ctx || !this.master) return;
    // the same sound is not repeated within a moment: a burst of kills is one thud, not a drum roll
    const now = this.ctx.currentTime;
    if (now - (this.last.get(cue) ?? -9) < (cue === "kill" || cue === "coin" ? 0.25 : 0.12)) return;
    this.last.set(cue, now);
    switch (cue) {
      case "quest-accept": this.run([[NOTE.E5, 0], [NOTE.A5, 0]], 0.16, 0.11); break;
      case "quest-done": this.run([[NOTE.C5, 0], [NOTE.E5, 0], [NOTE.G5, 0], [NOTE.C6, 0]], 0.2, 0.085, "triangle", 0.2); break;
      case "level":
        this.run([[NOTE.G4, 0], [NOTE.C5, 0], [NOTE.E5, 0], [NOTE.G5, 0]], 0.18, 0.1, "triangle", 0.2);
        [NOTE.C5, NOTE.E5, NOTE.G5, NOTE.C6].forEach(f => this.tone({ freq: f, at: 0.42, length: 0.7, type: "sine", gain: 0.12 }));
        break;
      case "kill": this.noise(0, 0.1, 500, 160, 0.22, "lowpass"); this.tone({ freq: 140, at: 0, length: 0.11, type: "sine", gain: 0.2, to: 60 }); break;
      case "coin": this.tone({ freq: 1760, at: 0, length: 0.09, gain: 0.1 }); this.tone({ freq: 2349, at: 0.06, length: 0.16, gain: 0.1 }); break;
      case "item": this.tone({ freq: 520, at: 0, length: 0.09, type: "sine", gain: 0.16, to: 780 }); break;
      case "item-rare": [NOTE.G5, 988, NOTE.E6].forEach((f, i) => this.tone({ freq: f, at: i * 0.06, length: 0.32, type: "sine", gain: 0.12 })); break;
      case "death": this.tone({ freq: 330, at: 0, length: 0.7, type: "sawtooth", gain: 0.12, to: 110 }); this.noise(0, 0.5, 600, 120, 0.1, "lowpass"); break;
      case "boss-kill":
        this.noise(0, 0.25, 300, 120, 0.2, "lowpass");
        this.run([[NOTE.C4, 0], [NOTE.G4, 0], [NOTE.C5, 0], [NOTE.E5, 0], [NOTE.G5, 0]], 0.22, 0.12, "triangle", 0.2);
        [NOTE.C5, NOTE.E5, NOTE.G5, NOTE.C6].forEach(f => this.tone({ freq: f, at: 0.7, length: 1, type: "triangle", gain: 0.12 }));
        break;
      case "boss-wipe": this.run([[NOTE.E4, 0], [NOTE.D4, 0], [NOTE.B3, 0]], 0.5, 0.32, "triangle", 0.18); this.noise(0, 1, 400, 90, 0.09, "lowpass"); break;
      case "pvp-win": this.run([[NOTE.G4, 0], [NOTE.C5, 0], [NOTE.E5, 0], [NOTE.G5, 0]], 0.2, 0.1, "square", 0.08); this.tone({ freq: NOTE.C6, at: 0.45, length: 0.6, gain: 0.12 }); break;
      case "pvp-loss": this.run([[NOTE.D4, 0], [NOTE.B3, 0]], 0.45, 0.3, "triangle", 0.16); break;
      case "zone": this.noise(0, 0.6, 300, 1400, 0.07); break;
      case "flight": this.noise(0, 1, 250, 1800, 0.09); break;
      case "skill": this.tone({ freq: 1200, at: 0, length: 0.05, type: "triangle", gain: 0.1 }); this.tone({ freq: 1500, at: 0.07, length: 0.05, type: "triangle", gain: 0.1 }); break;
      case "group": this.run([[NOTE.E5, 0], [NOTE.G5, 0]], 0.18, 0.1, "sine", 0.12); break;
      case "instance": this.noise(0, 0.8, 220, 70, 0.2, "lowpass"); this.tone({ freq: 80, at: 0, length: 0.7, type: "sine", gain: 0.14, to: 50 }); break;
    }
  }
}
