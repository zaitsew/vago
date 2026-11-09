# 2026-11-10 — Direction: silent by day, taught in the evening

Status: direction for Gate 1. Nothing here changes the default app. D6 (primary platform) is open.

## The owner's words

> "macos tool distracts me a bit when asks on every website if I'm working or not" (2026-10-29)

> "let's make Vago more autonomous and let him decide for myself what is productive and what is
> not." (2026-11-08)

> "let's come up with the main metric - % of productive time" (2026-11-08)

## What the data says

Six days tracked, 0 focus sessions, 0 moves, 0 learned rules (`./check.sh usage`, brief 03).
Tracking alone changed nothing, and the daytime question taught nothing: an answer lasted until
04:00 and never became a rule.

## The job

Know, at a glance, how much of today was productive, without being interrupted to get there.

## Three moments that matter

1. **During work: silence.** No question about a place, ever (shipped in zaitsew/vago#19).
   Unsure places count as neutral and wait. The only daytime panels are ones the owner started:
   the focus nudge and the move reminder.
2. **In the evening: one short review.** At most five places Vago was unsure about, largest
   first. One answer each: Work or Waste. Each answer becomes a rule, so tomorrow has fewer.
   Target: under 20 seconds. This is where "decide for myself" is taught.
3. **Any time: one number.** Productive % today across devices, in the menu bar and the widget
   (already shipped). The review moves it; nothing else asks for attention.

## Gate 1 slice: the evening review, two variants, Mac only

Behind Settings > Lab > "Evening review". Default "Day window" keeps today's behaviour.

| Variant | Shape | Structural question it answers |
|---|---|---|
| A. Cards | One place per card, the AI's reason under it, ← Waste / Work →, keys or buttons, dots for progress. | Is one decision at a time faster to finish? |
| B. List | All unsure places in one compact sheet, a Work / Waste switch per row, one Done. | Is seeing the whole day at once better than speed? |

Both use the existing correction path (`correctCall`): minutes move, a `.review` rule is learned.
Pass mark for Gate 2: three evenings in a row finished, zero daytime questions.

## Cut, for now

The morning plan (Loco's Today), friction at the limit, the merged day ribbon on the iPhone, and
a new popover layout. Each waits for the owner's pick at Gate 1; the night rules allow one flow.
