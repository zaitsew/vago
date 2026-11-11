# Dossier: Core loop — what Vago does to change behaviour

Journey: an ordinary workday: start work, drift to a feed, come back, end the day

Fill each part. Parts 2 to 5 take one item per line, labelled `guideline`, `observation` or
`hypothesis`, for example `- guideline: five or fewer tabs by default (source, link)`.
A popular app or a post is never evidence by itself.

## Owner's words and earlier picks

Verbatim, dated. Sources: `docs/PRODUCT.md`, `~/.teyla/intent/vago.md`, the 9 Nov sprint brief.

What the product is for:
- 29 Oct (kickoff): "Develop a simple app - "Vago" - that will count time spent on procrastination and work across my devices."
- 29 Oct: "Overall, my target - not to spend more than 30 min on procrastination a day."
- 29 Oct: "It should AI-native focus app - like Forest, but AI-native"
- 9 Nov: "I need to fully reimagine tool that will radically improve my productivity and decrease procrastination."
- 2026 goals: "stop losing time on scrolling social medias and procrastinating".

What hurts today:
- 29 Oct and 9 Nov: "macos tool distracts me a bit when asks on every website if I'm working or not."
- 8 Nov: "Vago is very buggy - i cannot see the full vago popup after i expanded some block. It is also poorly designed."
- 9 Nov: "iOS version crashes when I try to launch it".

What he asked Vago to do:
- 8 Nov: "let's make Vago more autonomous and let him decide for myself what is productive and what is not."
- 8 Nov: "let's come up with the main metric - % of productive time (100% - procrastination time spent on bullshit like scrolling social media)."
- 8 Nov: "I also wanna see a macos / ios app or widget where i can see my day statistics across the day across devices."
- 5 Nov: "remind me to do some exercises when i work non-stop with my laptop (more than 90 minutes, for example)".

Earlier picks: none in `teyla taste` for vago. The 10 Nov direction (zaitsew/vago#20,
`docs/decisions/2026-11-10-silent-day-evening-review.md`) was an agent proposal for Gate 1;
the owner has not picked Cards or List and has not answered D6 (primary platform).

## Usage

Read on 11 Nov 2026 at about 23:15 from the owner's Mac store
(`~/Library/Application Support/Vago/state.json` and `usage.json`), read-only, aggregated here;
nothing was copied into the repo. Mac app 0.1.0 from main (#21).

| Signal | Value |
|---|---|
| Days with data, Mac | 6 (29 Oct, 7–11 Nov) |
| Days with data, iPhone | 0: five iPhone day rows exist, every counter is 0 |
| Waste minutes per Mac day | 5, 15, 65, 21, 21, 15 (median 18; limit 30) |
| Productive share per Mac day | 79, 24, 82, 92, 90, 97 % |
| Today (11 Nov), active minutes | 473: rule 128 (27%), AI sure 142 (30%), unsure 202 (43%) |
| Unsure places waiting for review today | 786 sessions; all 202 unsure minutes count as neutral |
| Sessions today | 1,326; median length 6 s; 845 shorter than 10 s |
| Corrections ever made (overrides, custom rules) | 0 and 0 |
| Learned rules | 0 (`auto_rules=0`) |
| Focus sessions, last 7 days | 0 |
| Move breaks | 1 done |
| Evening review | offered on 11 Nov (the store keeps only the last day offered); never finished: 0 corrections. Whether it was opened is not recorded anywhere. |
| AI "work" verdicts on ambiguous places | 8 Nov 362 of 385, 9 Nov 320/370, 10 Nov 1,445/1,484, 11 Nov 7,399/7,689 (96%) |
| Today by app | Chrome 330 min, Claude 55, Codex 47, Telegram 33 |

- observation: tracking alone has run 6 days with no action from the owner: 0 focus sessions, 0 corrections, 0 rules.
- observation: 43% of today's active time is unclassified and counted as neutral, so the 97% share is inflated by unknown time. The share reads high on the days with the most unsure time.
- observation: the AI calls 96% of ambiguous minutes "work"; the "it's all research" guard (PRODUCT.md rule 6) is the only brake.
- observation: Chrome is 70% of active time. Work and waste share one app, so any block or delay must act per site, not per app.
- observation: the evening review would show 786 items today; at 2 s each that is 26 minutes, not the 20 s target of the 10 Nov direction.
- observation: the iPhone has never sent a counted minute, so cross-device numbers today are Mac-only.

Top three jobs on the current Mac build, steps counted from the code (see the job table
below). Seconds are estimates with the keystroke-level model (1.1 s per point-and-click,
1.2 s per mental step, 0.3 s per window open); they were not timed on the running app,
because the menu-bar app is not reachable by the computer-use tools.

| Job | Steps on the current build | Clicks | Est. seconds | What blocks it |
|---|---|---|---|---|
| 1a. Glance: today's productive % | read the menu bar (`😄 97%`) | 0 | ~1 | the number hides 43% unknown time |
| 1b. Glance: what pulled today down | menu bar → popover → **Day** → read "Top waste" | 2 | ~5 | the popover does not name the biggest waste place |
| 2a. Correct the place in front | popover → **Wrong?** → Work / Neutral / Waste | 3 | ~5 | only the place in front; hidden for rule-neutral places |
| 2b. Correct a call from today | popover → **Day** → scroll to "Vago's calls" → find the row → pick | 3 + scroll | ~9 | the list shows the top 8 by time; a call ranked 9th or lower cannot be corrected; no past days |
| 3. Evening review, default (Day window) | 20:00 panel → **Review** → Day window → 8 rows, 3 choices each | 1 + 8 | ~21 | reaches 8 of 786 unsure items today (1%); the panel closes itself after 60 s |
| 3. Evening review, Lab Cards / List | **Review** → up to 5 places, Work or Waste | 1 + 5 | ~13 | reaches 5 of 786 (0.6%); List loses picks if closed with the title-bar button |

- observation: no job that changes behaviour (start a focus block, stop a drift) appears in the top three, because the build has no such job by default; focus sessions exist and were started 0 times in 7 days.
- observation: the popover has no scroll and no height cap since commit `40a5950` (8 Nov); a two-line move row grows it (`Mac/PopoverView.swift:31-32`, `:236`). This is the owner's "cannot see the full vago popup" and is a bug to fix outside the design cycle.
- observation: nothing records whether the evening panel was seen, opened or dismissed (`usage.json` has no review counter); only "offered" and answers are stored.

## Guidelines

No HIG page rules on anti-procrastination loops. The platform rules and the research that act
as guidelines here (research run on 11 Nov by a Sonnet 5.5 lane, sources opened unless marked):

- guideline: Apple Screen Time / Family Controls give the iPhone one supported lever: a shield on chosen apps (`ManagedSettings`), configured by the app (`ShieldConfiguration`). The Mac has no Screen Time API; Vago's Mac lever is its own panel. (Apple developer documentation; Vago already ships the iPhone shield, `docs/ARCHITECTURE.md`.)
- guideline (peer-reviewed): friction at the moment of opening works. one sec, Grüning et al., PNAS 2023, N=280, 6 weeks: 36% of attempted opens abandoned, attempts −37%, actual opens −57%; in the N=500 follow-up the "dismiss" option did most, the delay less, the reflective message nothing. https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409
- guideline (peer-reviewed): self-set limits are taken up and work. Allcott, Gentzkow & Song, AER 2022, ~2,000 adults: a limit tool cut social-media and browser time 22 min/day (17%) over 12 weeks; 89% set binding limits unpaid. https://conference.nber.org/conf_papers/f157494.pdf
- guideline (peer-reviewed): soft friction keeps users better than lockout. InteractOut, CHI 2024, 42 people, 5 weeks: opens −17.0% more than a timed lockout, acceptance +25.4%. https://arxiv.org/pdf/2401.16668
- guideline (peer-reviewed): tracking alone did not lower use. Zimmermann & Sobolev 2023, N=112, pre-registered: the self-monitoring-only control arm "did not lower their usage". https://pubmed.ncbi.nlm.nih.gov/36577008/
- guideline (peer-reviewed): interruptions during work cost stress and effort, even when the work gets done. Mark, Gudith & Klocke, CHI 2008. https://ics.uci.edu/~gmark/chi08-mark.pdf
- guideline (peer-reviewed, effect shrinking): if-then plans help goal attainment: d = 0.65 in 2006 (94 tests); the 2024 update gives d = 0.36, 0.15 bias-corrected (2024 numbers unverified, from a search summary).
- observation: no controlled study shows that a daily plan-against-actual review, a Forest-style timer or a "why are you opening this?" message alone reduces distraction time.
- observation: day-30 retention for health and productivity apps is about 3–8% (vendor blogs, unverified); about 30% of wearable trackers are abandoned (Fadhil 2019 review, secondary figure).

## How other products solve it

Patterns read from the products' own pages or papers; marked where not opened this session.

| Product | What it does to behaviour | Pattern worth taking |
|---|---|---|
| one sec (one-sec.app; PNAS 2023) | a breath-and-wait screen when a chosen app opens, with "I don't want to open" as the main button | friction only on places the user chose; the exit is the big button |
| ScreenZen (screenzen.co, not opened) | a growing delay before a chosen app opens, a limit on opens per day | the delay grows with each open |
| Opal (opal.so impact survey) | scheduled blocks and "deep focus" sessions; 94% of 2,000+ surveyed members say less distracted (self-selected, no control) | sessions with a start, not all-day blocking |
| Apple Screen Time (support.apple.com) | self-set daily limits per app or category, "Ignore limit" for 15 min | the limit is the user's own number; one tap to pass |
| Freedom / Cold Turkey (freedom.to, getcoldturkey.com, not opened) | hard blocklists on a schedule, locked mode | strong while on; the lockout pattern loses users (InteractOut) |
| RescueTime (rescuetime.com) | passive tracking, a productivity score, Focus Sessions that block | the score alone is a mirror; the blocking is opt-in |
| Timing (timingapp.com) and Rize (rize.io, not opened) | passive Mac tracking, automatic categories, AI summaries | automatic classification; no lever of its own |
| Forest (forestapp.cc) | a tree grows while you stay off the phone | a session he starts; no study found |
| Beeminder (beeminder.com) | money at stake on a self-set goal | commitment; paid stakes are out of scope (no money flows in Vago) |
| Todoist (he uses it daily; todoist.com) | Today list | the plan for the day already lives there; Vago need not own it |

- observation: the products with published behaviour effects (one sec, Screen Time limits in Allcott) act at the moment of opening on places the user named; the trackers (RescueTime, Timing, Rize) publish no controlled effect.
- observation: Vago today is in the tracker group on the Mac and in the friction group on the iPhone (intent shield), which has recorded nothing.

## Practitioner reports

Not searched on X this session (timebox). Items from vendor surveys and blogs are listed
above as company data and are unverified.

- observation (unverified): Opal reports a 1 h 23 min/day drop from self-reported baselines (company blog, search summary only).
- observation (unverified): MindShift (N=25, 5 weeks) reports −12% to −14% open frequency from prompts at open; MindPhone (N=28) similar; both small.

## Second opinion (Grok 4.7, 11 Nov, $0.19)

Given the question in words, with no files and no private data (brief: the aggregate numbers
above). Its verdict: the core loop is the right first decision; platform and the waste list
come after it, because the iPhone has recorded nothing and "what counts as waste" matters only
once a loop acts on it. It recommends plan-and-protect, cut down: he names one to three waste
places and a delay fires only on those.

Where it disagrees with this session's first draft:
- The draft's option A had four parts (morning tasks, budget, delay, evening review). Grok: that repeats the ritual he already skips; the 786-item evening pile is the daytime interruption moved to the evening. Applied: the recommended option now has two parts, and the evening review leaves the loop.
- Grok: if the classifier picks the targets, the delay trains him to tap through, and dual-use apps are one sec's known failure mode. Applied: he names the places; Vago may propose them from his data, he confirms.
- Grok: hard blocking during work hours fails because his work lives in the browser. Agreed (Chrome is 70% of his active time).
- Grok cites a work-start cue ("after coffee, open the repo") as part of the loop. Not applied here: the start of work is decision 06.

## Hypotheses

- **H1.** A mirror changes nothing for him. Supported: 6 days, 0 actions. *Refuted if* in the next 7 days with option 2 the waste minutes fall below 15/day with no other change.
- **H2.** He can name his waste places himself, and they are few. *Refuted if* he cannot name three in 30 seconds (the test task), or the three cover less than half of the AI's waste minutes over a week.
- **H3.** A 5-second delay with "Close" as the big button cuts opens of those places by a third or more within two weeks, without him switching it off. *Refuted if* opens fall less than 20% or he disables it in the first week.
- **H4.** Daytime silence outside his list is what he values most. *Refuted if* he asks for nudges on places outside his list.
