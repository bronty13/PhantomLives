import { describe, expect, it } from 'vitest';
import { PLAYER_TEMPLATE } from '../src/creator/generated/playerTemplate';
import { buildSingleFileHtml, PAYLOAD_MARKER } from '../src/creator/deploy/injectPayload';
import { demoBundle } from '../src/shared/factory';

// Exercises the REAL embedded player template (committed stub on a fresh checkout,
// the built bundle after `npm run build`). Either way it must carry the marker and
// accept an injected payload to become a self-contained quiz file.
describe('real player template integration', () => {
  it('carries the payload marker', () => {
    expect(PLAYER_TEMPLATE).toContain(PAYLOAD_MARKER);
    expect(PLAYER_TEMPLATE).toContain('id="root"');
  });

  it('injects a quiz into a self-contained html with no marker left', () => {
    const { quiz, branding } = demoBundle();
    const { filename, html } = buildSingleFileHtml(PLAYER_TEMPLATE, quiz, branding, '2026-06-05T00:00:00Z');
    expect(filename.endsWith('.html')).toBe(true);
    expect(html).not.toContain(PAYLOAD_MARKER);
    expect(html).toContain('window.__QUIZ__=');
    // No external <script src> / <link href> that would break offline / file://.
    expect(html).not.toMatch(/<script[^>]+src="https?:\/\//);
    expect(html).not.toMatch(/<link[^>]+href="https?:\/\//);
  });
});
