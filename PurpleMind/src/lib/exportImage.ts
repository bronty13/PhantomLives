import { toPng, toSvg } from 'html-to-image';
import { getNodesBounds, getViewportForBounds, type Node } from '@xyflow/react';
import jsPDF from 'jspdf';
import { base64FromDataUrl, base64FromString } from './base64';

const PADDING = 0.12; // fraction of frame kept as margin around the map
const MIN_ZOOM = 0.3;
const MAX_ZOOM = 2;

interface RenderResult {
  /** base64 of the file bytes, ready for the Rust `save_export` command. */
  base64: string;
  /** raster data URL (also used as the PDF image source). */
  pngDataUrl?: string;
  width: number;
  height: number;
}

function frameFor(nodes: Node[]): { width: number; height: number } {
  const bounds = getNodesBounds(nodes);
  // Generous default frame so a tiny map still exports at a usable size.
  const width = Math.max(1024, Math.ceil(bounds.width) + 240);
  const height = Math.max(768, Math.ceil(bounds.height) + 240);
  return { width, height };
}

function viewportEl(): HTMLElement {
  const el = document.querySelector<HTMLElement>('.react-flow__viewport');
  if (!el) throw new Error('Canvas not ready — open a map first.');
  return el;
}

function bgColor(): string {
  return getComputedStyle(document.body).backgroundColor || '#ffffff';
}

/** Compute the transform that fits all nodes into the export frame. */
function fitOptions(nodes: Node[], width: number, height: number) {
  const bounds = getNodesBounds(nodes);
  const vp = getViewportForBounds(bounds, width, height, MIN_ZOOM, MAX_ZOOM, PADDING);
  return {
    backgroundColor: bgColor(),
    width,
    height,
    style: {
      width: `${width}px`,
      height: `${height}px`,
      transform: `translate(${vp.x}px, ${vp.y}px) scale(${vp.zoom})`,
    },
  };
}

export async function renderPng(nodes: Node[]): Promise<RenderResult> {
  const { width, height } = frameFor(nodes);
  const dataUrl = await toPng(viewportEl(), { ...fitOptions(nodes, width, height), pixelRatio: 2 });
  return { base64: base64FromDataUrl(dataUrl), pngDataUrl: dataUrl, width, height };
}

export async function renderSvg(nodes: Node[]): Promise<RenderResult> {
  const { width, height } = frameFor(nodes);
  const dataUrl = await toSvg(viewportEl(), fitOptions(nodes, width, height));
  // toSvg yields a URI-encoded (not base64) data URL; decode to raw markup.
  const comma = dataUrl.indexOf(',');
  const svg = decodeURIComponent(dataUrl.slice(comma + 1));
  return { base64: base64FromString(svg), width, height };
}

export async function renderPdf(nodes: Node[]): Promise<RenderResult> {
  const png = await renderPng(nodes);
  const orientation = png.width >= png.height ? 'landscape' : 'portrait';
  const pdf = new jsPDF({ orientation, unit: 'px', format: [png.width, png.height] });
  pdf.addImage(png.pngDataUrl!, 'PNG', 0, 0, png.width, png.height);
  const buffer = pdf.output('arraybuffer');
  // jsPDF arraybuffer → base64 without an extra dep.
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return { base64: btoa(binary), width: png.width, height: png.height };
}
