import { useMemo } from 'react';
import type { DocNode, DocType, OutputMode } from '../../shared/model';
import { serialize } from '../../shared/serialize';
import { charCountStatus } from '../../shared/validate/charCount';
import { findEmoji } from '../../shared/validate/emoji';
import { buildSanitizeReport } from '../../shared/sanitize';

export function ValidatorPanel({
  doc,
  mode,
  docType,
}: {
  doc: DocNode;
  mode: OutputMode;
  docType: DocType;
}) {
  const { count, emoji, report } = useMemo(() => {
    const html = serialize(doc, mode);
    return {
      count: charCountStatus(doc, mode, docType),
      emoji: findEmoji(html),
      report: buildSanitizeReport(html),
    };
  }, [doc, mode, docType]);

  return (
    <div className="validator">
      <div className={`counter ${count.level}`}>
        <div className="counter-bar">
          <div className="counter-fill" style={{ width: `${count.fraction * 100}%` }} />
        </div>
        <div className="counter-text">
          {count.count.toLocaleString()} / {count.limit.toLocaleString()} characters
          {count.level === 'over' && <strong> — over the limit! NiteFlirt will reject or cut this.</strong>}
          {count.level === 'warn' && <span> — approaching the limit.</span>}
        </div>
      </div>

      {emoji.length > 0 && (
        <div className="alert danger">
          ⚠ {emoji.length} emoji found ({emoji.map((e) => e.emoji).join(' ')}). NiteFlirt strips an emoji
          <strong> and everything after it</strong> on save — remove them before copying.
        </div>
      )}

      {!report.clean &&
        report.messages.map((m, i) => (
          <div key={i} className="alert warn">
            {m}
          </div>
        ))}

      {emoji.length === 0 && report.clean && count.level !== 'over' && (
        <div className="alert ok">✓ Looks good — safe to copy into NiteFlirt.</div>
      )}
    </div>
  );
}
