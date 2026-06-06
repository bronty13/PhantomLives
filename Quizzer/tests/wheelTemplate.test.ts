import { describe, expect, it } from 'vitest';
import { WHEEL_TEMPLATE } from '../src/creator/generated/wheelTemplate';
import { buildWheelSingleFileHtml, PAYLOAD_MARKER } from '../src/creator/deploy/injectPayload';
import { demoWheel } from '../src/shared/factory';

// Exercises the REAL embedded wheel template (committed stub on a fresh checkout,
// the built bundle after `npm run build`). Either way it must carry the marker and
// accept an injected wheel payload to become a self-contained wheel file.
describe('real wheel template integration', () => {
  it('carries the payload marker and a root mount', () => {
    expect(WHEEL_TEMPLATE).toContain(PAYLOAD_MARKER);
    expect(WHEEL_TEMPLATE).toContain('id="root"');
  });

  it('injects a wheel into a self-contained html with no marker left', () => {
    const { wheel, branding } = demoWheel();
    const { filename, html } = buildWheelSingleFileHtml(
      WHEEL_TEMPLATE,
      wheel,
      branding,
      '2026-06-06T00:00:00Z',
    );
    expect(filename.endsWith('.html')).toBe(true);
    expect(html).not.toContain(PAYLOAD_MARKER);
    expect(html).toContain('window.__QUIZ__=');
    expect(html).toContain('"kind":"wheel"');
    // No external <script src> / <link href> that would break offline / file://.
    expect(html).not.toMatch(/<script[^>]+src="https?:\/\//);
    expect(html).not.toMatch(/<link[^>]+href="https?:\/\//);
  });
});
