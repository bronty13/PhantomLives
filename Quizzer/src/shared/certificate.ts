// Completion certificate — a class-style PDF built with jsPDF (built-in fonts only,
// matching the RachelUGC invoice/cert pattern). Generated locally in the player.

import { jsPDF } from 'jspdf';

export interface CertificateOptions {
  respondentName: string;
  quizName: string;
  dateText: string;
  scorePct: number;
  colors: { primary: string; accent: string; text: string };
  logoDataUri?: string;
}

function hexToRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return [40, 40, 40];
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function generateCertificate(opts: CertificateOptions): jsPDF {
  const doc = new jsPDF({ unit: 'pt', format: 'letter', orientation: 'landscape' });
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  const [pr, pg, pb] = hexToRgb(opts.colors.primary);
  const [ar, ag, ab] = hexToRgb(opts.colors.accent);
  const [tr, tg, tb] = hexToRgb(opts.colors.text);

  // Decorative double border.
  doc.setDrawColor(pr, pg, pb);
  doc.setLineWidth(3);
  doc.rect(24, 24, W - 48, H - 48);
  doc.setDrawColor(ar, ag, ab);
  doc.setLineWidth(1);
  doc.rect(34, 34, W - 68, H - 68);

  const cx = W / 2;

  // Optional logo, centered near the top.
  if (opts.logoDataUri) {
    try {
      const fmt = opts.logoDataUri.includes('image/png') ? 'PNG' : 'JPEG';
      doc.addImage(opts.logoDataUri, fmt, cx - 40, 56, 80, 50, undefined, 'FAST');
    } catch {
      /* ignore unsupported logo formats — certificate still renders */
    }
  }

  doc.setTextColor(pr, pg, pb);
  doc.setFont('times', 'bold');
  doc.setFontSize(34);
  doc.text('Certificate of Completion', cx, 150, { align: 'center' });

  doc.setTextColor(tr, tg, tb);
  doc.setFont('times', 'normal');
  doc.setFontSize(14);
  doc.text('This certifies that', cx, 195, { align: 'center' });

  doc.setTextColor(ar, ag, ab);
  doc.setFont('times', 'bolditalic');
  doc.setFontSize(30);
  doc.text(opts.respondentName || 'Respondent', cx, 240, { align: 'center' });

  doc.setTextColor(tr, tg, tb);
  doc.setFont('times', 'normal');
  doc.setFontSize(14);
  doc.text('has successfully completed', cx, 280, { align: 'center' });

  doc.setFont('times', 'bold');
  doc.setFontSize(20);
  doc.text(opts.quizName, cx, 312, { align: 'center', maxWidth: W - 160 });

  doc.setFont('times', 'normal');
  doc.setFontSize(13);
  doc.text(
    `Score: ${Math.round(opts.scorePct)}%      Date: ${opts.dateText}`,
    cx,
    346,
    { align: 'center' },
  );

  // Signature block.
  const sigY = H - 96;
  const sigX = cx;
  doc.setTextColor(ar, ag, ab);
  doc.setFont('times', 'italic');
  doc.setFontSize(26);
  doc.text('Quizzer', sigX, sigY, { align: 'center' });
  doc.setDrawColor(tr, tg, tb);
  doc.setLineWidth(0.8);
  doc.line(sigX - 110, sigY + 8, sigX + 110, sigY + 8);
  doc.setTextColor(tr, tg, tb);
  doc.setFont('times', 'normal');
  doc.setFontSize(11);
  doc.text('Authorized Signature', sigX, sigY + 26, { align: 'center' });

  return doc;
}

export function certificateBlob(opts: CertificateOptions): Blob {
  return generateCertificate(opts).output('blob');
}
