import { useState } from "react";
import { Check, LoaderCircle, X } from "lucide-react";
import { api } from "../lib/api";
import { guideAction, type GuideProposal, type Trip } from "../lib/model";

export default function GuideReview({
  proposal,
  trip,
  apply,
  dismiss,
}: {
  proposal: GuideProposal;
  trip: Trip;
  apply: (trip: Trip) => void;
  dismiss: () => void;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const action = guideAction(trip.id, proposal);
  async function confirm() {
    if (!action) return;
    setBusy(true);
    setError("");
    try {
      const result = await api<Trip | { trip: Trip }>(action.path, action.body);
      apply("trip" in result ? result.trip : result);
      dismiss();
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "This change could not be applied.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="proposal-note">
      <span className="eyebrow">REVIEW BEFORE APPLYING</span>
      <p>{proposal.summary}</p>
      {proposal.data?.change && (
        <div className="guide-diff">
          {(["kept", "moved", "removed", "added"] as const).map((k) => (
            <div key={k}>
              <strong>{k}</strong>
              {proposal.data!.change![k].map((item, i) => (
                <span key={i}>{item.name}</span>
              ))}
            </div>
          ))}
        </div>
      )}
      {action ? (
        <div className="dialog-actions">
          <button
            className="button secondary"
            disabled={busy}
            onClick={dismiss}
          >
            <X size={14} />
            Keep my plan
          </button>
          <button className="button primary" disabled={busy} onClick={confirm}>
            {busy ? (
              <LoaderCircle size={14} className="spin" />
            ) : (
              <Check size={14} />
            )}
            Apply this change
          </button>
        </div>
      ) : (
        <p>
          Review booking options in Stays & flights. Ari cannot complete
          purchases.
        </p>
      )}
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
