import { MapPin, Wallet } from "lucide-react";
import { money, type Stop } from "../lib/model";

export type GuideCard =
  | {
      type: "place";
      place_id: string;
      name: string;
      match: number;
      notes: Record<string, string>;
    }
  | { type: "stop"; item: Stop }
  | {
      type: "budget";
      budget: { currency: string; spent: number; remaining: number };
    }
  | {
      type: "story";
      story: { title?: string; text?: string; message?: string };
    };

export default function GuideCards({ cards }: { cards: GuideCard[] }) {
  return (
    <div className="guide-cards">
      {cards.map((card, index) => {
        if (card.type === "place")
          return (
            <article key={card.place_id} className="guide-result">
              <MapPin size={17} />
              <div>
                <strong>{card.name}</strong>
                <p>{Object.values(card.notes ?? {}).join(" · ")}</p>
              </div>
              <span className="pill">{card.match}% match</span>
            </article>
          );
        if (card.type === "stop")
          return (
            <article key={index} className="guide-result">
              <MapPin size={17} />
              <div>
                <strong>{card.item.name}</strong>
                <p>
                  {card.item.start.slice(11, 16)} · {card.item.reason}
                </p>
              </div>
            </article>
          );
        if (card.type === "budget")
          return (
            <article key={index} className="guide-result">
              <Wallet size={17} />
              <div>
                <strong>
                  {money(card.budget.remaining, card.budget.currency)} remaining
                </strong>
                <p>
                  {money(card.budget.spent, card.budget.currency)} spent so far
                </p>
              </div>
            </article>
          );
        if (card.type === "story")
          return (
            <article key={index} className="guide-result">
              <div>
                <strong>{card.story.title}</strong>
                <p>{card.story.text ?? card.story.message}</p>
              </div>
            </article>
          );
        return null;
      })}
    </div>
  );
}
