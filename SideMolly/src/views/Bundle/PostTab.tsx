// Bundle workspace → Post tab. Routes by bundleType to the flavor-
// specific runner. Falls back to the generic checklist (Phase 7) for
// any bundle type we don't have a dedicated runner for.
//
//   content  → 🎬 ContentRunner (Phase 8)
//   custom   → 🎁 CustomRunner  (Phase 9)
//   fansite  → 📅 FanSiteRunner (Phase 10)
//   other    → GenericRunner    (Phase 7 fallback)

import { ContentRunner } from './ContentRunner';
import { CustomRunner } from './CustomRunner';
import { FanSiteRunner } from './FanSiteRunner';
import { GenericRunner } from './GenericRunner';
import { useCallback, useEffect, useState } from 'react';
import { getBundle, type BundleDetail, type BundleSummary } from '../../data/bundles';

interface Props {
  summary: BundleSummary;
}

export function PostTab({ summary }: Props) {
  // Pull the full BundleDetail (manifest + files) so the runners
  // can read description / categories / delivery / fan_days.
  const [detail, setDetail] = useState<BundleDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      setDetail(await getBundle(summary.uid));
    } catch (e) {
      setError(String(e));
    }
  }, [summary.uid]);

  useEffect(() => { refresh(); }, [refresh]);

  if (error) {
    return (
      <div className="sm-card text-sm" style={{ color: '#7a0000', background: '#ffe4e4' }}>
        ⚠ {error}
      </div>
    );
  }
  if (!detail) {
    return (
      <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Loading…
      </div>
    );
  }

  switch (summary.bundleType) {
    case 'content':
      return <ContentRunner summary={summary} detail={detail} />;
    case 'custom':
      return <CustomRunner summary={summary} detail={detail} />;
    case 'fansite':
      return <FanSiteRunner summary={summary} detail={detail} />;
    default:
      return <GenericRunner summary={summary} />;
  }
}
