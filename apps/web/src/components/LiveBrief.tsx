import { useEffect, useState } from "react";
import {
  ArrowUpRight,
  BookOpen,
  Check,
  Clock,
  MapPin,
  Volume2,
} from "lucide-react";
import { api } from "../lib/api";
import type { Day, Trip } from "../lib/model";

export default function LiveBrief({ trip, day }: { trip: Trip; day: Day }) {
  const next = day.items.find((s) => s.status !== "done");
  const [story, setStory] = useState(""),
    [busy, setBusy] = useState(false);
  useEffect(
    () => () => {
      if ("speechSynthesis" in window) speechSynthesis.cancel();
    },
    [],
  );
  async function tell() {
    if (!next) return;
    setBusy(true);
    try {
      if (trip.demo) {
        setStory(
          "This is a sample itinerary. Create a trip to hear source-backed stories from the Arivo guide.",
        );
        return;
      }
      const result = await api<{ text?: string; message?: string }>(
        `/v1/places/${encodeURIComponent(next.place_id)}/story`,
        { length: "30s", audience: "casual" },
      );
      setStory(
        result.text ??
          result.message ??
          "A verified story is unavailable for this place right now.",
      );
    } catch (e) {
      setStory(e instanceof Error ? e.message : "Story unavailable.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="glass live-brief">
      <div className="live-next">
        <span className="eyebrow">
          <span className="live-dot" />
          NEXT UNVISITED STOP · SELECTED DAY
        </span>
        <h2>{next?.name ?? "A day well wandered."}</h2>
        <p>
          {next ? (
            <>
              <Clock size={13} />
              {next.start.slice(11, 16)} planned · {next.duration_min} minutes
            </>
          ) : (
            <>
              <Check size={14} />
              You’ve visited every stop. Time for a little rest.
            </>
          )}
        </p>
      </div>
      {next && (
        <div className="live-actions">
          <a
            className="button primary"
            href={`https://www.google.com/maps/dir/?api=1&destination=${next.lat},${next.lon}&travelmode=walking`}
            target="_blank"
            rel="noreferrer"
          >
            <MapPin size={16} />
            Take me there
            <ArrowUpRight size={15} />
          </a>
          <button className="button secondary" disabled={busy} onClick={tell}>
            <BookOpen size={16} />
            {busy ? "Finding the story…" : "Tell me its story"}
          </button>
        </div>
      )}
      {story && (
        <div className="live-story">
          <p>{story}</p>
          {"speechSynthesis" in window && (
            <button
              className="text-button"
              onClick={() => {
                speechSynthesis.cancel();
                const utterance = new SpeechSynthesisUtterance(story);
                utterance.lang = "en";
                speechSynthesis.speak(utterance);
              }}
            >
              <Volume2 size={15} />
              Read aloud
            </button>
          )}
        </div>
      )}
    </section>
  );
}
