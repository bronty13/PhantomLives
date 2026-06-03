import { useEffect, useState } from 'react';
import type { NodeRow } from '../../../../shared/types';
import { basename } from '../common/format';

const api = window.purpleTree;

interface Props {
  scanId: string;
  focusId: number;
  onNavigate: (id: number) => void;
}

export default function Breadcrumb({ scanId, focusId, onNavigate }: Props): JSX.Element {
  const [crumbs, setCrumbs] = useState<NodeRow[]>([]);

  useEffect(() => {
    let cancelled = false;
    void api.getBreadcrumb(scanId, focusId).then((c) => {
      if (!cancelled) setCrumbs(c);
    });
    return () => {
      cancelled = true;
    };
  }, [scanId, focusId]);

  return (
    <div className="breadcrumb">
      {crumbs.map((c, i) => (
        <span key={c.id} className="crumb">
          <button className="crumb-btn" onClick={() => onNavigate(c.id)} title={c.path}>
            {i === 0 ? c.name : basename(c.name)}
          </button>
          {i < crumbs.length - 1 && <span className="crumb-sep">›</span>}
        </span>
      ))}
    </div>
  );
}
