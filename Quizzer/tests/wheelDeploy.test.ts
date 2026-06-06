import { describe, expect, it } from 'vitest';
import JSZip from 'jszip';
import { buildWheelSingleFileHtml, PAYLOAD_MARKER } from '../src/creator/deploy/injectPayload';
import {
  buildWheelZipPlan,
  externalizeWheelAssets,
  packZip,
  packZipBytes,
} from '../src/creator/deploy/buildZip';
import type { Branding, Wheel } from '../src/shared/model';
import { bytesToDataUri } from '../src/shared/dataurl';

const FAKE_TEMPLATE = `<!doctype html><html><head><!--QUIZ_PAYLOAD--></head><body><div id="root"></div><script type="module">/*wheel*/</script></body></html>`;

const branding: Branding = {
  id: 'b1', name: 'Brand', updatedAt: 0,
  colors: { primary: '#111', secondary: '#222', accent: '#333', bg: '#fff', text: '#000' },
  font: { kind: 'builtin', family: 'Inter' },
};

function wheelWith(extra: Partial<Wheel> = {}): Wheel {
  return {
    id: 'w1', name: 'Prize Wheel!', descriptionHtml: '<p>Spin!</p>',
    choices: [
      { id: 'a', text: 'Coffee', weight: 1 },
      { id: 'b', text: 'Gift Card', weight: 1 },
    ],
    spinsPermitted: 0, soundDefaultOn: true, pdfResultCount: 1,
    resultLabel: 'You won', spinSeconds: 6,
    brandingId: 'b1', createdAt: 0, updatedAt: 0,
    ...extra,
  };
}

describe('buildWheelSingleFileHtml', () => {
  const { filename, html } = buildWheelSingleFileHtml(FAKE_TEMPLATE, wheelWith(), branding, 'now');

  it('names the file from the wheel, slugified', () => {
    expect(filename).toBe('prize-wheel.html');
  });
  it('sets window.__QUIZ__ before the player module and leaves no marker', () => {
    expect(html).toContain('window.__QUIZ__=');
    expect(html).not.toContain(PAYLOAD_MARKER);
    expect(html.indexOf('window.__QUIZ__=')).toBeLessThan(html.indexOf('<script type="module">'));
  });
  it('ships choice labels in plaintext (they are public on the wheel)', () => {
    expect(html).toContain('Coffee');
    expect(html).toContain('Gift Card');
    expect(html).toContain('"kind":"wheel"');
  });
  it('escapes < to avoid </script> breakouts', () => {
    const tricky = wheelWith({ name: '</script><b>x', descriptionHtml: '<p></script></p>' });
    const out = buildWheelSingleFileHtml(FAKE_TEMPLATE, tricky, branding, 'now').html;
    expect(out).toContain('\\u003c');
  });
});

describe('externalizeWheelAssets', () => {
  const bigMedia = bytesToDataUri('video/mp4', new Uint8Array(400 * 1024));
  const smallMedia = bytesToDataUri('image/png', new Uint8Array(1024));

  it('moves large inline media to assets/', () => {
    const res = externalizeWheelAssets(
      wheelWith({ media: { kind: 'inline', mime: 'video/mp4', dataUri: bigMedia } }),
      branding,
    );
    expect(res.files.length).toBe(1);
    expect(res.files[0].path).toMatch(/^assets\/media-\d+\.mp4$/);
    expect(res.wheel.media?.kind).toBe('file');
  });
  it('keeps small inline media inline', () => {
    const res = externalizeWheelAssets(
      wheelWith({ media: { kind: 'inline', mime: 'image/png', dataUri: smallMedia } }),
      branding,
    );
    expect(res.files.length).toBe(0);
    expect(res.wheel.media?.kind).toBe('inline');
  });
});

describe('buildWheelZipPlan + packZip', () => {
  const bigLogo = bytesToDataUri('image/png', new Uint8Array(400 * 1024));
  const plan = buildWheelZipPlan(
    FAKE_TEMPLATE,
    wheelWith(),
    { ...branding, logo: { kind: 'inline', mime: 'image/png', dataUri: bigLogo } },
    'now',
  );

  it('loads the payload via a classic external script', () => {
    expect(plan.indexHtml).toContain('<script src="./data.js"></script>');
    expect(plan.indexHtml).not.toContain('window.__QUIZ__=');
    expect(plan.dataJs.startsWith('window.__QUIZ__=')).toBe(true);
  });
  it('zips index.html + data.js + externalized assets', async () => {
    const bytes = await packZipBytes(plan);
    const zip = await JSZip.loadAsync(bytes);
    expect(zip.file('index.html')).toBeTruthy();
    expect(zip.file('data.js')).toBeTruthy();
    expect(Object.keys(zip.files).some((p) => p.startsWith('assets/'))).toBe(true);
  });
  it('packZip wraps the bytes in a Blob', async () => {
    const blob = await packZip(plan);
    expect(blob.size).toBeGreaterThan(0);
  });
});
