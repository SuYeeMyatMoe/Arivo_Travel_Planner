import { useState, type FormEvent } from "react";
import { Camera, Check, CreditCard, LoaderCircle, Plus } from "lucide-react";
import { api } from "../lib/api";
import {
  money,
  type Expense,
  type ReceiptDraft,
  type Trip,
} from "../lib/model";

export default function ReceiptLens({
  trip,
  onSaved,
}: {
  trip: Trip;
  onSaved: (expense: Expense) => void;
}) {
  const [text, setText] = useState(""),
    [draft, setDraft] = useState<ReceiptDraft | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [saved, setSaved] = useState(false);
  async function parse() {
    setBusy(true);
    setError("");
    setSaved(false);
    try {
      const result = await api<{ draft: ReceiptDraft }>("/v1/lens/receipt", {
        text,
        currency_hint: trip.currency,
      });
      setDraft(result.draft);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Receipt could not be read.");
    } finally {
      setBusy(false);
    }
  }
  async function confirm(e: FormEvent) {
    e.preventDefault();
    if (!draft?.total || draft.total <= 0) return;
    setBusy(true);
    setError("");
    try {
      if (!trip.demo)
        await api(`/v1/trips/${trip.id}/expenses`, {
          merchant: draft.merchant,
          amount: draft.total,
          currency: draft.currency,
          category: draft.category,
          source: "receipt_lens",
        });
      onSaved({
        id: crypto.randomUUID(),
        merchant: draft.merchant ?? "Receipt",
        amount: draft.total,
        currency: draft.currency,
        category: draft.category,
      });
      setSaved(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Expense could not be saved.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <div className="section-header">
        <div>
          <span className="eyebrow">LESS ADMIN. MORE EXPLORING.</span>
          <h1>A little clarity for your receipts.</h1>
        </div>
      </div>
      <div className="lens-grid">
        <section className="glass panel">
          <Camera className="large-icon" />
          <h2>Your receipts, in the picture.</h2>
          <p className="muted">
            Paste receipt text and let Arivo extract the details. You’ll check
            the amount before anything is added to your budget.
          </p>
          <label className="receipt-label">
            Receipt text
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              maxLength={8000}
              placeholder={"Coffee shop\nCappuccino (2) 900\nTotal JPY 900"}
              rows={8}
            />
          </label>
          <button
            className="button primary full"
            disabled={text.trim().length < 3 || busy}
            onClick={parse}
          >
            {busy ? (
              <LoaderCircle size={16} className="spin" />
            ) : (
              <Camera size={16} />
            )}
            Read this receipt
          </button>
          <p className="context-note">
            Only this text is sent to your travel service. Camera OCR remains
            available in the mobile app.
          </p>
          {error && (
            <p className="inline-error" role="alert">
              {error}
            </p>
          )}
        </section>
        <section className="glass panel">
          <span className="eyebrow">REVIEW & RECORD</span>
          <h2>Every little moment, accounted for.</h2>
          {draft ? (
            <form onSubmit={confirm} className="trip-form">
              <div className="receipt-lines">
                {draft.lines.map((line, i) => (
                  <div key={i}>
                    <span>
                      {line.name} × {line.qty}
                    </span>
                    <strong>{money(line.amount, draft.currency)}</strong>
                  </div>
                ))}
              </div>
              <label>
                Merchant
                <input
                  required
                  maxLength={120}
                  value={draft.merchant ?? ""}
                  onChange={(e) =>
                    setDraft({ ...draft, merchant: e.target.value })
                  }
                />
              </label>
              <div className="form-grid two">
                <label>
                  Total
                  <input
                    required
                    type="number"
                    min="0.01"
                    max="1000000"
                    step="0.01"
                    value={draft.total ?? ""}
                    onChange={(e) =>
                      setDraft({ ...draft, total: Number(e.target.value) })
                    }
                  />
                </label>
                <label>
                  Currency
                  <select
                    value={draft.currency}
                    onChange={(e) =>
                      setDraft({ ...draft, currency: e.target.value })
                    }
                  >
                    {[
                      ...new Set([
                        draft.currency,
                        "JPY",
                        "USD",
                        "MYR",
                        "EUR",
                        "SGD",
                      ]),
                    ].map((c) => (
                      <option key={c}>{c}</option>
                    ))}
                  </select>
                </label>
              </div>
              <label>
                Category
                <select
                  value={draft.category}
                  onChange={(e) =>
                    setDraft({ ...draft, category: e.target.value })
                  }
                >
                  {[
                    "food",
                    "transport",
                    "activities",
                    "shopping",
                    "accommodation",
                    "other",
                  ].map((c) => (
                    <option key={c}>{c}</option>
                  ))}
                </select>
              </label>
              {draft.warnings.map((w) => (
                <p className="context-note" key={w}>
                  {w}
                </p>
              ))}
              <button className="button primary full" disabled={busy || saved}>
                {saved ? (
                  <>
                    <Check size={16} />
                    Added to your budget
                  </>
                ) : (
                  <>
                    <Plus size={16} />
                    Confirm & add expense
                  </>
                )}
              </button>
            </form>
          ) : (
            <div className="quiet-empty">
              <CreditCard size={35} />
              <p>
                The details will appear here.
                <br />
                You stay in control of what gets saved.
              </p>
            </div>
          )}
        </section>
      </div>
    </>
  );
}
