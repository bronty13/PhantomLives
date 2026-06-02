import { describe, it, expect } from 'vitest';
import {
  clampSettings,
  computeOutputSize,
  frameCount,
  frameDelayMs,
  paletteColors,
  MAX_DURATION_S,
  MAX_FPS,
  MAX_WIDTH,
  MIN_FPS,
  type GifSettings,
} from './encodeGif';

const base: GifSettings = {
  startSec: 0,
  endSec: 3,
  fps: 12,
  outputWidth: 320,
  quality: 'high',
  crop: null,
  caption: null,
};

describe('frameDelayMs', () => {
  it('is the rounded reciprocal of fps in ms', () => {
    expect(frameDelayMs(10)).toBe(100);
    expect(frameDelayMs(12)).toBe(83); // round(1000/12) = 83
    expect(frameDelayMs(25)).toBe(40);
  });
});

describe('frameCount', () => {
  it('is span * fps, at least 1', () => {
    expect(frameCount(0, 3, 10)).toBe(30);
    expect(frameCount(1, 2, 12)).toBe(12);
    expect(frameCount(5, 5, 12)).toBe(1); // zero-length clip → single frame
    expect(frameCount(2, 1, 10)).toBe(1); // inverted → clamped to 1
  });
});

describe('paletteColors', () => {
  it('maps quality to a color budget', () => {
    expect(paletteColors('high')).toBe(256);
    expect(paletteColors('medium')).toBe(128);
    expect(paletteColors('low')).toBe(64);
  });
});

describe('clampSettings', () => {
  it('clamps fps into [MIN_FPS, MAX_FPS]', () => {
    expect(clampSettings({ ...base, fps: 1 }, 10).fps).toBe(MIN_FPS);
    expect(clampSettings({ ...base, fps: 999 }, 10).fps).toBe(MAX_FPS);
  });

  it('clamps output width into [64, MAX_WIDTH]', () => {
    expect(clampSettings({ ...base, outputWidth: 10 }, 10).outputWidth).toBe(64);
    expect(clampSettings({ ...base, outputWidth: 5000 }, 10).outputWidth).toBe(MAX_WIDTH);
  });

  it('caps clip length to MAX_DURATION_S by trimming the end', () => {
    const c = clampSettings({ ...base, startSec: 0, endSec: 60 }, 120);
    expect(c.endSec - c.startSec).toBeLessThanOrEqual(MAX_DURATION_S);
    expect(c.endSec).toBe(MAX_DURATION_S);
  });

  it('keeps start/end within the source duration', () => {
    const c = clampSettings({ ...base, startSec: 8, endSec: 20 }, 5);
    expect(c.startSec).toBeLessThanOrEqual(5);
    expect(c.endSec).toBeLessThanOrEqual(5);
    expect(c.endSec).toBeGreaterThanOrEqual(c.startSec);
  });
});

describe('computeOutputSize', () => {
  it('keeps aspect ratio and forces even height with no crop', () => {
    const { width, height, sx, sy, sw, sh } = computeOutputSize(1920, 1080, null, 480);
    expect(width).toBe(480);
    expect(height).toBe(270); // 1080/1920 * 480 = 270 (even)
    expect([sx, sy, sw, sh]).toEqual([0, 0, 1920, 1080]);
  });

  it('forces an even height (odd rounds up)', () => {
    const { height } = computeOutputSize(100, 99, null, 100);
    expect(height % 2).toBe(0);
  });

  it('derives the source rect from a normalized crop', () => {
    const { sx, sy, sw, sh, width } = computeOutputSize(1000, 1000, { x: 0.25, y: 0.25, w: 0.5, h: 0.5 }, 480);
    expect([sx, sy, sw, sh]).toEqual([250, 250, 500, 500]);
    // Target width never exceeds the cropped source width.
    expect(width).toBeLessThanOrEqual(500);
  });

  it('never upscales beyond the (cropped) source width', () => {
    const { width } = computeOutputSize(200, 200, null, MAX_WIDTH);
    expect(width).toBe(200);
  });
});
