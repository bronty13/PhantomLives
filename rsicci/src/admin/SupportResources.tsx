// Universal, optional support-resources screen. Shown when DFI_SAFETY ≥ 3 or
// DFI_FUNCTION ≥ 3 (an administration-time feature, NOT a score). It never alerts
// staff and never draws a clinical/legal conclusion — it is participant-controlled
// information only. The resource list is intentionally generic; a real deployment
// substitutes IRB-approved, locale-appropriate resources.

interface Props {
  onContinue: () => void
}

export default function SupportResources({ onContinue }: Props) {
  return (
    <div className="screen support">
      <h2>A note, and some resources</h2>
      <p>
        Some questions touched on safety or day-to-day impact. Sharing this is completely optional,
        and nothing here is a diagnosis or a judgment. If you would find it helpful, these kinds of
        resources are available to anyone:
      </p>
      <ul>
        <li>A trusted clinician or your usual healthcare provider.</li>
        <li>A confidential helpline or crisis line in your area.</li>
        <li>A trusted friend, peer, or community support contact.</li>
      </ul>
      <p className="muted">
        This screen is shown to everyone whose answers touched these topics. No one is notified, and
        you can continue the survey whenever you like.
      </p>
      <button className="primary" onClick={onContinue}>
        Continue
      </button>
    </div>
  )
}
