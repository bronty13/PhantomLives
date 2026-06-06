// Zip deploy: externalize large assets to assets/, reference them by relative path,
// and load the payload via a classic <script src="./data.js"> (works under file://).

import JSZip from 'jszip';
import type { AssetRef, Branding, Quiz } from '../../shared/model';
import { buildPayload } from '../../shared/payload';
import { assetByteSize, INLINE_LIMIT_BYTES } from '../../shared/assets';
import { dataUriToBytes, extForMime, jsonForScript } from '../../shared/dataurl';
import { slugify } from '../../shared/util';
import { injectScript } from './injectPayload';

export interface AssetFile {
  path: string; // e.g. assets/logo.png
  bytes: Uint8Array;
}

interface Externalized {
  quiz: Quiz;
  branding: Branding;
  files: AssetFile[];
}

/** Move inline assets larger than the limit out to assets/ and rewrite their refs. */
export function externalizeAssets(
  quiz: Quiz,
  branding: Branding,
  limit = INLINE_LIMIT_BYTES,
): Externalized {
  const files: AssetFile[] = [];
  let counter = 0;

  function maybeExternalize(ref: AssetRef | undefined, base: string): AssetRef | undefined {
    if (!ref || ref.kind !== 'inline') return ref;
    if (assetByteSize(ref) <= limit) return ref;
    const { mime, bytes } = dataUriToBytes(ref.dataUri);
    const path = `assets/${base}-${counter++}.${extForMime(mime)}`;
    files.push({ path, bytes });
    return { kind: 'file', mime, path, name: ref.name };
  }

  const newBranding: Branding = {
    ...branding,
    logo: maybeExternalize(branding.logo, 'logo'),
    font:
      branding.font.kind === 'custom'
        ? { ...branding.font, ttf: maybeExternalize(branding.font.ttf, 'font') ?? branding.font.ttf }
        : branding.font,
  };

  const newQuiz: Quiz = {
    ...quiz,
    introMedia: maybeExternalize(quiz.introMedia, 'intro'),
    questions: quiz.questions.map((q) => ({ ...q, image: maybeExternalize(q.image, 'qimg') })),
  };

  return { quiz: newQuiz, branding: newBranding, files };
}

export interface ZipPlan {
  filename: string;
  indexHtml: string;
  dataJs: string;
  files: AssetFile[];
}

export function buildZipPlan(
  template: string,
  quiz: Quiz,
  branding: Branding,
  generatedAt: string,
): ZipPlan {
  const ext = externalizeAssets(quiz, branding);
  const payload = buildPayload(ext.quiz, ext.branding, 'zip', generatedAt);
  return {
    filename: `${slugify(quiz.name)}.zip`,
    indexHtml: injectScript(template, '<script src="./data.js"></script>'),
    dataJs: `window.__QUIZ__=${jsonForScript(payload)};`,
    files: ext.files,
  };
}

function assemble(plan: ZipPlan): JSZip {
  const zip = new JSZip();
  zip.file('index.html', plan.indexHtml);
  zip.file('data.js', plan.dataJs);
  for (const f of plan.files) zip.file(f.path, f.bytes);
  return zip;
}

/** Assemble the zip as raw bytes (testable without a browser Blob). */
export function packZipBytes(plan: ZipPlan): Promise<Uint8Array> {
  return assemble(plan).generateAsync({ type: 'uint8array', compression: 'DEFLATE' });
}

export function packZip(plan: ZipPlan): Promise<Blob> {
  return assemble(plan).generateAsync({ type: 'blob', compression: 'DEFLATE' });
}
