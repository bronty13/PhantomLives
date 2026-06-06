import type { Branding } from '../../shared/model';
import { resolveAsset } from '../../shared/assets';

export function BrandBar({ branding, quizName }: { branding: Branding; quizName: string }) {
  const logo = resolveAsset(branding.logo);
  return (
    <div className="brandbar">
      {logo && <img src={logo} alt="" />}
      <span className="qname">{quizName}</span>
    </div>
  );
}
