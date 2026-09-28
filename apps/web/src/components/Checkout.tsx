import { useRef, useState, type FormEvent } from "react";
import { Check, LoaderCircle, ShieldCheck } from "lucide-react";
import { api } from "../lib/api";
import { fromMinor, money, type Money } from "../lib/model";
type Offer = {
  offer_id: string;
  title: string;
  subtitle: string;
  price: Money;
  sandbox: boolean;
  cancellation_policy: string;
  lines?: { label: string; amount: Money }[];
};
type Transaction = {
  id: string;
  state: string;
  offer: Offer;
  booking_reference?: string;
  failure_reason?: string;
  needs_reconciliation?: boolean;
};
export default function Checkout({
  offer,
  tripId,
  travelers,
}: {
  offer: Offer;
  tripId: string;
  travelers: number;
}) {
  const [transaction, setTransaction] = useState<Transaction | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [names, setNames] = useState(() =>
    Array.from({ length: Math.min(travelers, 9) }, () => ({
      given_name: "",
      family_name: "",
    })),
  );
  const key = useRef(crypto.randomUUID());
  const current = transaction?.offer ?? offer;
  const ready =
    transaction &&
    ["PRICE_CONFIRMED", "PRICE_CHANGED"].includes(transaction.state);
  async function prepare(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      setTransaction(
        await api<Transaction>(
          `/v1/trips/${tripId}/bookings`,
          { offer_id: offer.offer_id, travellers: names.length },
          undefined,
          key.current,
        ),
      );
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Could not check the latest price.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function confirm() {
    if (!transaction || !ready) return;
    setBusy(true);
    setError("");
    try {
      setTransaction(
        await api<Transaction>(`/v1/bookings/${transaction.id}/confirm`, {
          accepted_total_minor: current.price.amount_minor,
          travellers: names,
        }),
      );
    } catch (e) {
      setError(
        e instanceof Error ? e.message : "Confirmation could not be completed.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function refresh() {
    if (!transaction) return;
    setBusy(true);
    setError("");
    try {
      setTransaction(await api<Transaction>(`/v1/bookings/${transaction.id}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Status is unavailable.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="checkout">
      <span className="pill">
        {current.sandbox ? "SANDBOX · NO REAL BOOKING" : "PROVIDER OFFER"}
      </span>
      <p className="context-note">{current.subtitle}</p>
      <p className="detail-description">
        {current.cancellation_policy ||
          "Review the provider’s cancellation terms before confirming."}
      </p>
      <div className="receipt-lines">
        {current.lines?.map((line, i) => (
          <div key={i}>
            <span>{line.label}</span>
            <strong>
              {money(fromMinor(line.amount), line.amount.currency)}
            </strong>
          </div>
        ))}
      </div>
      <h3 className="checkout-total">
        {money(fromMinor(current.price), current.price.currency)}
        <small>
          Total for {names.length} traveler{names.length === 1 ? "" : "s"}
        </small>
      </h3>
      {transaction?.state === "PRICE_CHANGED" && (
        <p className="inline-error">
          The price changed. Review the new total above before confirming.
        </p>
      )}
      {!transaction ? (
        <form className="trip-form" onSubmit={prepare}>
          {names.map((name, i) => (
            <fieldset key={i}>
              <legend>Traveler {i + 1}</legend>
              <div className="form-grid two">
                <label>
                  Given name
                  <input
                    required
                    maxLength={60}
                    value={name.given_name}
                    onChange={(e) =>
                      setNames((n) =>
                        n.map((v, j) =>
                          i === j ? { ...v, given_name: e.target.value } : v,
                        ),
                      )
                    }
                  />
                </label>
                <label>
                  Family name
                  <input
                    required
                    maxLength={60}
                    value={name.family_name}
                    onChange={(e) =>
                      setNames((n) =>
                        n.map((v, j) =>
                          i === j ? { ...v, family_name: e.target.value } : v,
                        ),
                      )
                    }
                  />
                </label>
              </div>
            </fieldset>
          ))}
          <button className="button primary full" disabled={busy}>
            {busy ? (
              <LoaderCircle size={16} className="spin" />
            ) : (
              <ShieldCheck size={16} />
            )}
            Check the latest price
          </button>
        </form>
      ) : transaction.state === "CONFIRMED" ? (
        <div className="booking-confirmed" role="status">
          <Check size={24} />
          <h3>
            {current.sandbox
              ? "Sandbox booking confirmed"
              : "Booking confirmed"}
          </h3>
          <p>Reference: {transaction.booking_reference ?? transaction.id}</p>
        </div>
      ) : ready ? (
        <>
          <p className="context-note">
            {current.sandbox
              ? "This confirmation uses the sandbox provider and does not make a real purchase."
              : "Pressing the button below confirms the displayed total and requests payment."}
          </p>
          <button
            className="button primary full"
            disabled={busy}
            onClick={confirm}
          >
            {busy ? (
              <LoaderCircle size={16} className="spin" />
            ) : (
              <Check size={16} />
            )}
            Confirm {current.sandbox ? "sandbox booking" : "& pay"} ·{" "}
            {money(fromMinor(current.price), current.price.currency)}
          </button>
        </>
      ) : (
        <div className="context-note">
          <p>
            {transaction.failure_reason ??
              `Booking status: ${transaction.state.replaceAll("_", " ").toLowerCase()}.`}
            {transaction.needs_reconciliation
              ? " The provider result is pending. Check status before trying another booking."
              : ""}
          </p>
          <button
            className="button secondary"
            disabled={busy}
            onClick={refresh}
          >
            Check status
          </button>
        </div>
      )}
      {error && (
        <p className="inline-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
