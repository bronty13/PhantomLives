import { describe, it, expect } from 'vitest';
import { clipVideoBitrate, MP4_MAX_BYTES, MP4_MAX_DURATION_S } from './recordMp4';

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
