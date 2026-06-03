import { describe, it, expect } from 'vitest';
import {
  clipVideoBitrate,
  MP4_MAX_BYTES,
  MP4_MAX_DURATION_S,
  AVC_CANDIDATES,
  webCodecsClipSupported,
  bestClipEngine,
} from './recordMp4';

describe('clipVideoBitrate', () => {
  it('keeps a max-length clip under the 100 MB cap', () => {
    const bps = clipVideoBitrate(MP4_MAX_DURATION_S, true);
    // video + 128kbps audio over the full duration must fit under the cap.
    const totalBits = (bps + 128_000) * MP4_MAX_DURATION_S;
    expect(totalBits / 8).toBeLessThanOrEqual(MP4_MAX_BYTES);
  });

  it('clamps to at most 8 Mbps for short clips (where budget is huge)', () => {
    expect(clipVideoBitrate(2, true)).toBe(8_000_000);
  });

  it('never drops below 1 Mbps', () => {
    expect(clipVideoBitrate(99999, true)).toBe(1_000_000);
  });

  it('gives more video headroom when audio is excluded', () => {
    // At a duration where the budget binds (not clamped), no-audio >= audio.
    const d = 30;
    expect(clipVideoBitrate(d, false)).toBeGreaterThanOrEqual(clipVideoBitrate(d, true));
  });
});

describe('H.264 codec candidates', () => {
  it('tries the most-compatible profile (Baseline) first', () => {
    // Baseline 3.0 is the profile picky Windows players accept most reliably.
    expect(AVC_CANDIDATES[0]).toBe('avc1.42E01E');
  });

  it('only lists avc1 (H.264) strings', () => {
    expect(AVC_CANDIDATES.every((c) => c.startsWith('avc1.'))).toBe(true);
  });
});

describe('engine selection', () => {
  // The unit-test environment (node) has neither WebCodecs nor MediaRecorder.
  it('reports no WebCodecs support without the platform APIs', () => {
    expect(webCodecsClipSupported()).toBe(false);
  });

  it('returns null when no recording engine is available at all', () => {
    expect(bestClipEngine()).toBeNull();
  });
});
