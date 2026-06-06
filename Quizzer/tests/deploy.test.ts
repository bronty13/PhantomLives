import { describe, expect, it } from 'vitest';
import JSZip from 'jszip';
import { buildSingleFileHtml, injectScript, PAYLOAD_MARKER } from '../src/creator/deploy/injectPayload';
import { buildZipPlan, externalizeAssets, packZip, packZipBytes } from '../src/creator/deploy/buildZip';
import type { Branding, Quiz } from '../src/shared/model';
import { bytesToDataUri } from '../src/shared/dataurl';

const FAKE_TEMPLATE = `<!doctype html><html><head><!--QUIZ_PAYLOAD--></head><body><div id="root"></div><script type="module">/*player*/</script></body></html>`;

const branding: Branding = {
  id: 'b1', name: 'Brand', updatedAt: 0,
  colors: { primary: '#111', secondary: '#222', accent: '#333', bg: '#fff', text: '#000' },
  font: { kind: 'builtin', family: 'Inter' },
};

function quizWith(extra: Partial<Quiz> = {}): Quiz {
  return {
    id: 'q1', name: 'My Quiz!', introHtml: '<p>hi</p>', attempts: 3, randomizeQuestions: false,
    passingPct: 80, certificateEnabled: true, brandingId: 'b1', createdAt: 0, updatedAt: 0,
    questions: [
      { id: 'qa', type: 'mc', promptHtml: '<p>q</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: true, randomizeChoices: false, choices: [{ id: 'a', text: 'A' }, { id: 'b', text: 'SECRETANSWER' }], correctChoiceId: 'b' },
    ],
    ...extra,
  };
}

describe('injectScript', () => {
  it('replaces the marker exactly once', () => {
    const out = injectScript(FAKE_TEMPLATE, '<script>X</script>');
    expect(out).not.toContain(PAYLOAD_MARKER);
    expect(out).toContain('<script>X</script>');
  });
  it('throws when the marker is absent', () => {
    expect(() => injectScript('<html></html>', '<script>X</script>')).toThrow(/marker/);
  });
  it('treats the script as literal (no $-pattern expansion)', () => {
    const out = injectScript(FAKE_TEMPLATE, '<script>const a="$&$1";</script>');
    expect(out).toContain('$&$1');
  });
});

describe('buildSingleFileHtml', () => {
  const { filename, html } = buildSingleFileHtml(FAKE_TEMPLATE, quizWith(), branding, '2026-01-01T00:00:00Z');

  it('names the file from the quiz, slugified', () => {
    expect(filename).toBe('my-quiz.html');
  });
  it('sets window.__QUIZ__ before the player module', () => {
    expect(html).toContain('window.__QUIZ__=');
    expect(html.indexOf('window.__QUIZ__=')).toBeLessThan(html.indexOf('<script type="module">'));
  });
  it('leaves no marker and reveals no answer key in plaintext', () => {
    expect(html).not.toContain(PAYLOAD_MARKER);
    // Choice TEXT is legitimately visible (it's shown to the respondent); only
    // WHICH choice is correct is secret — that field is blanked + obfuscated.
    expect(html).toContain('"correctChoiceId":""');
    expect(html).not.toContain('"correctChoiceId":"b"');
  });
  it('escapes < to avoid </script> breakouts', () => {
    const tricky = quizWith({ name: '</script><b>x', introHtml: '<p></script></p>' });
    const out = buildSingleFileHtml(FAKE_TEMPLATE, tricky, branding, 'now').html;
    expect(out).toContain('\\u003c'); // < was escaped in the payload JSON
  });
});

describe('externalizeAssets', () => {
  const bigLogo = bytesToDataUri('image/png', new Uint8Array(400 * 1024));
  const smallLogo = bytesToDataUri('image/png', new Uint8Array(1024));

  it('moves large inline assets to assets/ files', () => {
    const res = externalizeAssets(quizWith(), { ...branding, logo: { kind: 'inline', mime: 'image/png', dataUri: bigLogo } });
    expect(res.files.length).toBe(1);
    expect(res.files[0].path).toMatch(/^assets\/logo-\d+\.png$/);
    expect(res.branding.logo).toMatchObject({ kind: 'file' });
  });
  it('keeps small inline assets inline', () => {
    const res = externalizeAssets(quizWith(), { ...branding, logo: { kind: 'inline', mime: 'image/png', dataUri: smallLogo } });
    expect(res.files.length).toBe(0);
    expect(res.branding.logo?.kind).toBe('inline');
  });
  it('externalizes a large per-question image', () => {
    const q = quizWith();
    q.questions[0].image = { kind: 'inline', mime: 'image/png', dataUri: bigLogo };
    const res = externalizeAssets(q, branding);
    expect(res.files.some((f) => f.path.startsWith('assets/qimg-'))).toBe(true);
    expect(res.quiz.questions[0].image?.kind).toBe('file');
  });
});

describe('buildZipPlan + packZip', () => {
  const bigLogo = bytesToDataUri('image/png', new Uint8Array(400 * 1024));
  const plan = buildZipPlan(FAKE_TEMPLATE, quizWith(), { ...branding, logo: { kind: 'inline', mime: 'image/png', dataUri: bigLogo } }, 'now');

  it('loads the payload via a classic external script, not inline/module', () => {
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
    const indexBack = await zip.file('index.html')!.async('string');
    expect(indexBack).toContain('<script src="./data.js"></script>');
  });
  it('packZip wraps the bytes in a Blob', async () => {
    const blob = await packZip(plan);
    expect(blob.size).toBeGreaterThan(0);
  });
});
