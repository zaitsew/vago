# Dossier: Primary platform — Mac or iPhone leads (D6)

Journey: the same workday: where the drift happens and where Vago acts

Fill each part. Parts 2 to 5 take one item per line, labelled `guideline`, `observation` or
`hypothesis`, for example `- guideline: five or fewer tabs by default (source, link)`.
A popular app or a post is never evidence by itself.

"Leads" means POLICY §14's primary platform: a feature is designed, built and accepted there
first; the other platform catches up in a parity train. Security and data-loss fixes ship to
both the same day either way.

## Owner's words and earlier picks

Verbatim, dated. Sources: `docs/PRODUCT.md`, `~/.teyla/intent/vago.md`, `design/decisions/01-core-loop/pick-note.md`.

- 29 Oct (kickoff): "Develop a simple app - "Vago" - that will count time spent on procrastination and work across my devices."
- 29 Oct: "Overall, my target - not to spend more than 30 min on procrastination a day."
- 8 Nov: "I also wanna see a macos / ios app or widget where i can see my day statistics across the day across devices."
- 9 Nov: "iOS version crashes when I try to launch it".
- 12 Nov (decision 01): "То есть я вижу это как иконку в controls menu - чтобы я визуально по изображению и цветам мог понять, какой сейчас мод стоит, и мог его переключить."

Earlier picks: decision 01, "1 + 3" (guard my list, with a block in work hours per place), built
on the Mac in #28–#32. Card 01 said "Drawn for the Mac, the default until card 02". He did not
object, but he was not asked about the platform either. `teyla.toml` says `primary = "ios"`.
That is POLICY §14's default, not his choice. The Mac carries a dated trigger: "across my
devices" (29 Oct).

## Usage

Read on 13 Nov 2026 from the owner's Mac store (`~/Library/Application Support/Vago/state.json`),
read-only, aggregated here; nothing was copied into the repo.

| Signal | Mac | iPhone |
|---|---|---|
| Days with a ledger row | 8 (28–29 Oct, 7–12 Nov) | 5 (29, 31 Oct, 8–10 Nov) |
| Counted minutes, all days | 817 work, 146 waste, 550 neutral | 0 on every row |
| Waste minutes per day | 5, 15, 65, 21, 21, 15, 4 (median 15; limit 30) | none recorded |
| Biggest app, 11 Nov | Chrome 330 of 473 active minutes (70%) | — |
| Build the owner has | 0.1.0 (1), 10 Nov, before the core loop; not running since 12 Nov 12:39 | TestFlight 0.1.0 (4), which fixes the 9 Nov launch crash (`docs/RELEASE.md`) |

- observation: every counted minute Vago has is a Mac minute. The iPhone has written five day rows, all zero.
- observation: the core loop of decision 01 exists only on the Mac (#28–#32). The iPhone has the older intent shield ("Work · 15 min / Scroll · 5 min").
- observation: the owner's phone time is unknown. His iPhone's Screen Time totals were not read, and Vago's iPhone counters never ran, so this decision cannot yet compare the two devices' waste.
- observation: the docs disagree on the iPhone channel. `docs/RELEASE.md` lists internal TestFlight builds 1–4; `docs/ARCHITECTURE.md` (Distribution) says TestFlight needs the Family Controls (Distribution) entitlement, which Apple grants by hand. Which one holds for the Screen Time extensions was not verified.

## Guidelines

- guideline: macOS has no third-party Screen Time API. Family Controls and Managed Settings are iOS and iPadOS only; Apple's forum answer is "currently for iOS only" (developer.apple.com/forums/thread/717569, thread/721295). The Mac lever is Vago's own panel, a tab closed by Apple Events, and a hidden app.
- guideline: on the iPhone, Screen Time gives an OS-enforced shield on chosen apps and web domains (`ManagedSettings`), configured by the app (`ShieldConfiguration`). It is the strongest lever either device offers, and the user cannot ignore it the way he can ignore a panel.
- guideline: on the iPhone, an app never sees what is on screen and never gets raw usage. It learns minutes only from threshold events (`DeviceActivityMonitor`). The per-app report runs in a sandboxed extension whose data cannot leave it (WWDC22 "What's new in Screen Time API", developer.apple.com/videos/play/wwdc2022/110336). No titles, no URLs, no per-site split inside an app.
- guideline: the Mac sees every second: the front app, the window title (Accessibility) and the browser tab's URL (Apple Events). It is the only device where work and waste inside one browser can be told apart (`docs/MAC.md`).
- guideline: POLICY §14: one primary per product; a second platform needs a dated trigger; feature PRs touch the primary only.

## How other products solve it

| Product | Leads on | Pattern worth taking |
|---|---|---|
| one sec (one-sec.app) | iPhone; Mac and browser extension later | the friction at opening lives where the OS allows it; the Mac copy is a browser extension |
| Opal (opal.so) | iPhone, Screen Time shields | phone-first blocking; the Mac app came years later |
| Freedom (freedom.to) | both, one blocklist synced | a session applies to every device at once |
| Cold Turkey (getcoldturkey.com) | desktop only | a hard desktop block; no phone |
| RescueTime (rescuetime.com) | desktop tracking, phone secondary | the desktop is where the time and the categories come from |
| Timing (timingapp.com) | Mac only | per-app and per-site time from the Mac alone |
| Apple Screen Time | iPhone first, Mac reads the same limits | one limit per app, shared across devices |

- observation: the blockers that act at the moment of opening lead on the iPhone, because that is where the OS gives them a shield. The trackers that classify time lead on the desktop, because that is where titles and URLs are visible.
- observation: Vago is both. Decision 01 made it a guard with a count, so the lever and the count must both work on the device that leads.

## Practitioner reports

- observation (not verified): developers report that Family Controls fails to authorize on Mac Catalyst, so an iPhone build running on a Mac gets no shield (developer.apple.com/forums/thread/814446).
- observation (verified in the repo): an earlier agent build shipped the iPhone intent shield first; it recorded no minutes in two weeks.

## Second opinion

- Grok 4.7 (13 Nov, short brief, aggregates only): "Lead with the Mac." Reasons: the count needs per-site URLs, and only the Mac has them; the Mac already has the data and the loop; acceptance should follow what can be seen. Risk named: if the phone is the real leak, a passing Mac day misses the goal. Test that flips it: if 7 days of iPhone Screen Time show social, Safari and entertainment over 30 minutes a day, or more than the Mac's waste, lead with the iPhone.
- Codex (GPT-6.1 Sol, 13 Nov, the same brief): "macOS leads." Reasons: it measures the goal today, it can tell work from waste inside Chrome, and its loop reaches the owner now. Risk named: the Mac median leaves out phone scrolling, and friction on the Mac may move scrolling to the phone. Test: the same Screen Time week; switch if phone waste beats Mac waste on most days.
- Where they differ: they do not on the pick. Codex adds the displacement risk (the Mac pause pushes scrolling to the phone), which is the strongest argument for keeping the iPhone shield alive while the Mac leads.
- The brief said iPhone TestFlight is blocked. `docs/RELEASE.md` shows TestFlight builds exist, so both opinions slightly overstate that blocker. Their pick rests on the other two reasons.

## Hypotheses

- hypothesis: the waste that matters for the 30-minute goal happens at the desk, inside Chrome. If so, the Mac leading moves the number; the iPhone leading does not.
- hypothesis: evening and bed-time scrolling happens on the phone. If so, a Mac-only day reads green while the goal is missed, and the iPhone's shield is the right lever.
- hypothesis: the phone test (7 days of iPhone Screen Time, social + entertainment per day) settles which hypothesis holds in one minute, without building anything.
