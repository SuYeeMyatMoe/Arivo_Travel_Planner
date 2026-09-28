# Arivo lightweight research plan

## Goal
Check that Arivo's three bets hold before we polish further:
1. One natural-language sentence is enough to start a trip.
2. A trip that adapts (Rescue / Plan B) is trusted more than a static itinerary.
3. Groups feel the plan is fair without a leaderboard.

## Participants (5–6, 45 min, remote or in person, KL-based to start)
| Segment | n | Screener |
|---|---|---|
| Friend group organiser (22–32) | 2 | planned a trip abroad with 3+ friends in the last 12 months |
| Couple | 1–2 | booked flights + stay themselves in the last 12 months |
| Family planner with an elderly parent or child | 1 | travels with someone who has mobility or pace limits |
| Weekend / domestic explorer | 1 | took a day or weekend trip within Malaysia in the last 3 months |

Recruit through community groups and personal networks. Offer a RM50 voucher. Get consent for recording and do not collect booking or passport data.

## Session guide
1. **Warm-up (5 min):** "Walk me through the last trip you planned. What tools, in what order?" Probe for tab-switching and group chat chaos.
2. **Past disruption (8 min):** "Tell me about a day that didn't go to plan." Probe what they did, who decided, and what it cost.
3. **Task A: onboarding (8 min, Flutter web build):** "Plan your next trip in one sentence." Measure time to first itinerary and edits in the first 60 s. Ask "What do you trust or not trust here?"
4. **Task B: Rescue (8 min):** "It starts raining at 2 pm." Participants use Rescue My Day and read the ChangeDiff. Ask "Would you apply this? What would you want to see first?"
5. **Task C: crew (8 min):** show two crew members' votes and the balanced evening. Ask "Does this feel fair to everyone? Who would complain?"
6. **Task D: booking trust (5 min):** show checkout with a SANDBOX badge and a price change. Ask "What would make you pay here instead of on the airline site?"
7. **Wrap-up (3 min):** "One thing that would make you use this on your next trip."

## Guerrilla test (15 min, 8–10 people, campus / co-working)
Only Tasks A and B. Record completion, time and the first words people say when they see the diff.

## What we measure (from spec §55)
| Metric | Target for MVP |
|---|---|
| Time to first itinerary | < 30 s from submitting the sentence |
| Itinerary accepted without edits | ≥ 60% of stops |
| Replan applied (Rescue) | ≥ 70% of sessions |
| Crew "fair" rating (1–5) | ≥ 4 |
| Numbers questioned ("where is this from?") | tracked qualitatively; drives provenance design |

## Synthesis
- Affinity-map quotes by bet. Tag each as **confirm / refute / new**.
- Output: the top 5 insights, each with evidence count, a representative quote and the design change it implies.
- Also update `design/DESIGN.md` and the `apps/mobile` backlog.

## Ethics
Participants can stop at any time. Recordings are deleted after 30 days. Quotes are anonymised. No real payment or booking data is used.
