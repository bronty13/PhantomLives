// Spin-result memorial PDF — built with jsPDF (built-in fonts only), mirroring the
// quiz certificate style. Generated locally in the wheel player. Lists the most
// recent result big, plus any prior spins the creator chose to include.

import { jsPDF } from 'jspdf';

export interface WheelResultEntry {
  label: string;
  at: string; // human-readable timestamp
}

export interface WheelResultOptions {
  wheelName: string;
  /** Caption above the winning prize (defaults to "You won"). */
  caption?: string;
  /** Results to memorialize, newest first. The first is shown large. */
  results: WheelResultEntry[];
  colors: { primary: string; accent: string; text: string };
  logoDataUri?: string;
}

function hexToRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec((hex ?? '').trim());
  if (!m) return [40, 40, 40];
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function generateWheelResult(opts: WheelResultOptions): jsPDF {
  const doc = new jsPDF({ unit: 'pt', format: 'letter', orientation: 'portrait' });
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  const [pr, pg, pb] = hexToRgb(opts.colors.primary);
  const [ar, ag, ab] = hexToRgb(opts.colors.accent);
  const [tr, tg, tb] = hexToRgb(opts.colors.text);
  const cx = W / 2;

  // Decorative double border.
  doc.setDrawColor(pr, pg, pb);
  doc.setLineWidth(3);
  doc.rect(24, 24, W - 48, H - 48);
  doc.setDrawColor(ar, ag, ab);
  doc.setLineWidth(1);
  doc.rect(34, 34, W - 68, H - 68);

  // Optional logo, centered near the top.
  if (opts.logoDataUri) {
    try {
      const fmt = opts.logoDataUri.includes('image/png') ? 'PNG' : 'JPEG';
      doc.addImage(opts.logoDataUri, fmt, cx - 40, 56, 80, 50, undefined, 'FAST');
    } catch {
      /* ignore unsupported logo formats — page still renders */
    }
  }

  doc.setTextColor(pr, pg, pb);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(26);
  doc.text(opts.wheelName || 'Spin the Wheel', cx, 150, { align: 'center', maxWidth: W - 120 });

  doc.setTextColor(tr, tg, tb);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(14);
  doc.text(opts.caption?.trim() || 'You won', cx, 195, { align: 'center' });

  const winner = opts.results[0]?.label ?? '—';
  doc.setTextColor(ar, ag, ab);
  doc.setFont('times', 'bolditalic');
  doc.setFontSize(40);
  doc.text(winner, cx, 250, { align: 'center', maxWidth: W - 120 });

  if (opts.results[0]?.at) {
    doc.setTextColor(tr, tg, tb);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(12);
    doc.text(opts.results[0].at, cx, 282, { align: 'center' });
  }

  // History (prior spins), when the creator asked for more than the latest.
  if (opts.results.length > 1) {
    doc.setDrawColor(ar, ag, ab);
    doc.setLineWidth(0.6);
    doc.line(cx - 130, 312, cx + 130, 312);

    doc.setTextColor(pr, pg, pb);
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(13);
    doc.text('Spin history', cx, 338, { align: 'center' });

    doc.setTextColor(tr, tg, tb);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(11);
    let y = 360;
    const maxY = H - 80;
    for (let i = 0; i < opts.results.length; i++) {
      if (y > maxY) {
        doc.text(`… and ${opts.results.length - i} more`, cx, y, { align: 'center' });
        break;
      }
      const r = opts.results[i];
      doc.text(`${i + 1}.  ${r.label}${r.at ? `   (${r.at})` : ''}`, cx, y, {
        align: 'center',
        maxWidth: W - 140,
      });
      y += 18;
    }
  }

  // Footer signature.
  doc.setTextColor(ar, ag, ab);
  doc.setFont('times', 'italic');
  doc.setFontSize(20);
  doc.text('Quizzer', cx, H - 70, { align: 'center' });

  return doc;
}

export function wheelResultBlob(opts: WheelResultOptions): Blob {
  return generateWheelResult(opts).output('blob');
}
