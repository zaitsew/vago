# Vago — product

Vago counts the time you lose to procrastination and the time you spend working, on the
iPhone and the Mac. A live timer shows today's procrastination against a daily limit that
adapts to you. The goal is at most 30 minutes a day.

## The owner's words

From the kickoff (2026-10-29):

> Develop a simple app - "Vago" - that will count time spent on procrastination and work
> across my devices. Think how to count productive and unproductive time - by app usages (for
> example, instagram - unproductive), or are there better approaches? Because social media,
> for example, can be used for work. It would be also great to use real-time activity and show
> timer in the top counting real-time unproductive time for the day - and marking it in
> green-yellow-red or changing emoji from happy to upset. The limit should adjust a bit
> depending on average values, like with Garmin recommended daily steps. Overall, my target -
> not to spend more than 30 min on procrastination a day.

> Decide yourself. The smarter the system - better. It should AI-native focus app - like
> Forest, but AI-native

From a later request (2026-11-05):

> Let's add to Vago features to remind me to do some exercises when i work non-stop with my
> laptop (more than 90 minutes, for example) - it can be integrated with Iron-U or without it

From a later request (2026-11-08):

> I also wanna see a macos / ios app or widget where i can see my day statistics across the day
> across devices. And let's come up with the main metric - % of productive time (100% -
> procrastination time spent on bullshit like scrolling social media). And let's make Vago more
> autonomous and let him decide for myself what is productive and what is not.

From the 2026 goals list: "stop losing time on scrolling social medias and procrastinating".

## What each part serves

| Part | Serves |
|---|---|
| Productive share, the main metric | "% of productive time (100% - procrastination time spent on bullshit …)" |
| Hour slots per device | "my day statistics across the day across devices" |
| Vago decides, the owner corrects | "let him decide for myself what is productive and what is not" |
| Four buckets and the classifier (below) | "Think how to count productive and unproductive time … social media, for example, can be used for work" |
| Rules, the AI judge with context, learned rules, the intent check | "The smarter the system - better" |
| Menu-bar timer (Mac), widget and Live Activity (iPhone) | "show timer in the top counting real-time unproductive time for the day" |
| Mood: colour and emoji | "marking it in green-yellow-red or changing emoji from happy to upset" |
| Adaptive limit | "The limit should adjust a bit depending on average values, like with Garmin" |
| 30-minute floor | "not to spend more than 30 min on procrastination a day" |
| Focus sessions that grow a tree | "like Forest, but AI-native" |
| iCloud totals across devices | "across my devices" |
| Move breaks (Mac) | "remind me to do some exercises when i work non-stop with my laptop (more than 90 minutes, for example)" |

## Buckets

Every second of foreground use falls in one bucket:

- **productive**: work tools (Xcode, Terminal, Notion, Linear, Mail, Figma, Claude, ChatGPT…).
- **neutral**: necessary but neither (Maps, Wallet, Settings, Phone, Calendar). Not counted.
- **procrastination**: feeds, games, video, news (TikTok, Reels, Netflix, Reddit…).
- **ambiguous**: apps that serve both (Instagram, YouTube, X, LinkedIn, Telegram, WhatsApp,
  Threads, Substack). The four signals below decide each session.

## The main metric: productive share

    productive share = 100% − procrastination / (work + neutral + procrastination)

- "100% minus the time spent on bullshit." Neutral time is not waste, so it counts on the
  productive side. Idle, locked and asleep time is not in it.
- A minute is a minute on every device. The iPhone adds what Screen Time reports for its
  waste, mixed and work lists; it cannot see its neutral time.
- Hidden ("—") below 15 active minutes, so two minutes of Reels at 09:00 do not read 0%.
- Whole percent. 100% only with no waste at all.
- Colour: green from 90% (30 minutes of waste in a 5-hour day), yellow from 75%, red below.
- The minutes of waste against the adaptive limit stay beside it: the share says whether the
  day aimed at the goals, the limit says whether scrolling stayed inside the budget.

Every device keeps its seconds per hour slot (04:00, 05:00 … 03:00), so the day can be drawn
as a timeline per device.

## Vago decides, the owner corrects

1. **Rules first.** Built-in rules, the owner's corrections and learned rules settle most use.
   The AI never overrides a rule: Reels, Shorts and Explore stay waste.
2. **The AI judges the rest.** Places a rule calls ambiguous (Instagram's home, YouTube, a
   browser with no URL) and places no rule knows go to Apple's on-device model. It sees the
   owner's goals, the title and address, the hour, how long the place has been in front, and
   what came just before ("Xcode (work)"). Nothing leaves the Mac.
3. **A sure verdict decides.** At 0.7 confidence or more the verdict counts. Below that, or
   with no verdict, the time is neutral: it does not move the share either way. Such calls are
   marked unsure.
4. **Corrections, not reviews.** Vago does not wait for answers. Its calls for the day are
   listed with the AI's reason; one tap corrects one, moves its minutes, and becomes a rule.
5. **Learned rules.** The same sure verdict (0.85 or more) on a place nothing knew, on three
   different days, becomes a rule. Never for an ambiguous place: three good YouTube days must
   not make all of YouTube work.
6. **A guard against "it's all research".** When on each of the last three days the AI judged
   at least 30 minutes on ambiguous places and called more than 80% of it work, its "work"
   verdicts on ambiguous places count as neutral until a day looks normal again or the owner
   corrects a call.
7. **Intent check (iPhone).** Ambiguous apps sit behind a Screen Time shield. It asks
   "Work or scroll?". *Work* unlocks the app for 15 minutes of use, counted as productive.
   *Scroll* unlocks 5 minutes, counted as procrastination. The iPhone cannot see what is on
   screen, so this is the one question Vago keeps asking.

Without the on-device model, ambiguous use counts as procrastination and is marked unsure, and
unknown use is neutral.

## Mood

Mood is the share of today's limit used:

| share | emoji | colour |
|---|---|---|
| < 25% | 😄 | green |
| < 50% | 🙂 | green |
| < 75% | 😐 | yellow |
| < 100% | 😟 | yellow |
| < 150% | 😣 | red |
| ≥ 150% | 😵 | red |

## Adaptive limit

Like Garmin's auto step goal, but the limit moves down:

- **Calibration**: the first 3 tracked days use a 60-minute limit and record a baseline.
- **Baseline**: the median of the calibration days, at least 30 minutes.
- **Each new day** starts from yesterday's limit:
  - yesterday at or under the limit: 5 minutes less;
  - yesterday more than 50% over: 5 minutes more;
  - otherwise unchanged.
- The limit never rises above the baseline or the 7-day median + 10 minutes, whichever is
  lower. It never falls below the 30-minute target.
- Limits are rounded to whole 5 minutes.

## Focus sessions (Forest, AI-native)

- Start a 25- or 50-minute session from the Mac menu or the iPhone app.
- A seedling 🌱 grows to a tree 🌳 as the session runs.
- During a session the iPhone shields procrastination and ambiguous apps. The Mac shows a
  "back to work?" nudge on the first distracting second.
- More than 60 seconds of procrastination wilts the tree 🥀. The session still counts as
  focus time up to that point.
- The garden counts this week's trees.

## Move breaks (Mac)

- A **streak** is unbroken time at the Mac, whatever the app. Five minutes away (no input,
  locked, asleep) is a break: the next use starts a new streak.
- After **90 minutes** (45, 60, 75 or 120 in Settings) a floating panel names one exercise of
  2 to 3 minutes with exact reps: squats, desk push-ups, a hip flexor stretch, a walk… No
  equipment, no floor. The moves rotate.
- Buttons: **I did it** (counts the move, starts a new streak), **Another** (the next move),
  **Later** (asks again in 15 minutes).
- A panel nobody answers closes after 90 seconds and asks once more 25 minutes later. After two
  unanswered panels it stops for this streak; only 🚶 stays in the menu bar. It never grows louder.
- It waits during a focus session and while the microphone is in use (a call), then one more
  minute, then until the next app switch (at most 3 minutes).
- The popover shows the time since the last break, today's moves, and **Not today**.
- No Iron U link yet: Iron U has no way to log a workout from another app, and a jump to another
  app is where a break gets dropped. Revisit when Iron U can take a logged move.

## Day

A day runs from 04:00 to 04:00 local time. Late-night scrolling belongs to the evening it
started in.

## Not in v1

- Cloud AI insights (weekly patterns, "your worst hour is 22:00"): v2, through the accounts
  hub on Haiku 5.5.
- Goals imported from Knut: v2.
- iPad, Android, web.
