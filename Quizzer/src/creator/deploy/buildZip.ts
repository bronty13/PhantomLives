// Zip deploy: externalize large assets to assets/, reference them by relative path,
// and load the payload via a classic <script src="./data.js"> (works under file://).

import JSZip from 'jszip';
import type { AssetRef, Branding, Quiz, Wheel } from '../../shared/model';
import { buildPayload } from '../../shared/payload';
import { buildWheelPayload } from '../../shared/wheelPayload';
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

interface WheelExternalized {
  wheel: Wheel;
  branding: Branding;
  files: AssetFile[];
}

/**
 * A shared "move large inline assets to assets/" helper used by both the quiz and
 * wheel deploy paths. The returned `ext` keeps one running counter so externalized
 * file names stay stable (logo-0, intro-1, …).
 */
function createExternalizer(limit: number) {
  const files: AssetFile[] = [];
  let counter = 0;
  function ext(ref: AssetRef | undefined, base: string): AssetRef | undefined {
    if (!ref || ref.kind !== 'inline') return ref;
    if (assetByteSize(ref) <= limit) return ref;
    const { mime, bytes } = dataUriToBytes(ref.dataUri);
    const path = `assets/${base}-${counter++}.${extForMime(mime)}`;
    files.push({ path, bytes });
    return { kind: 'file', mime, path, name: ref.name };
  }
  function branding(b: Branding): Branding {
    return {
      ...b,
      logo: ext(b.logo, 'logo'),
      font:
        b.font.kind === 'custom'
          ? { ...b.font, ttf: ext(b.font.ttf, 'font') ?? b.font.ttf }
          : b.font,
    };
  }
  return { files, ext, branding };
}

/** Move inline assets larger than the limit out to assets/ and rewrite their refs. */
export function externalizeAssets(
  quiz: Quiz,
  branding: Branding,
  limit = INLINE_LIMIT_BYTES,
): Externalized {
  const x = createExternalizer(limit);
  const newBranding = x.branding(branding);
  const newQuiz: Quiz = {
    ...quiz,
    introMedia: x.ext(quiz.introMedia, 'intro'),
    questions: quiz.questions.map((q) => ({ ...q, image: x.ext(q.image, 'qimg') })),
  };
  return { quiz: newQuiz, branding: newBranding, files: x.files };
}

/** Wheel variant — the only externalizable wheel asset is its optional media. */
export function externalizeWheelAssets(
  wheel: Wheel,
  branding: Branding,
  limit = INLINE_LIMIT_BYTES,
): WheelExternalized {
  const x = createExternalizer(limit);
  const newBranding = x.branding(branding);
  const newWheel: Wheel = { ...wheel, media: x.ext(wheel.media, 'media') };
  return { wheel: newWheel, branding: newBranding, files: x.files };
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

export function buildWheelZipPlan(
  template: string,
  wheel: Wheel,
  branding: Branding,
  generatedAt: string,
): ZipPlan {
  const ext = externalizeWheelAssets(wheel, branding);
  const payload = buildWheelPayload(ext.wheel, ext.branding, 'zip', generatedAt);
  return {
    filename: `${slugify(wheel.name)}.zip`,
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
