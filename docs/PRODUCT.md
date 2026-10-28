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

From the 2026 goals list: "stop losing time on scrolling social medias and procrastinating".

## What each part serves

| Part | Serves |
|---|---|
| Four buckets and the classifier (below) | "Think how to count productive and unproductive time … social media, for example, can be used for work" |
| Intent check, Mac context, AI verdict, nightly review | "The smarter the system - better" |
| Menu-bar timer (Mac), widget and Live Activity (iPhone) | "show timer in the top counting real-time unproductive time for the day" |
| Mood: colour and emoji | "marking it in green-yellow-red or changing emoji from happy to upset" |
| Adaptive limit | "The limit should adjust a bit depending on average values, like with Garmin" |
| 30-minute floor | "not to spend more than 30 min on procrastination a day" |
| Focus sessions that grow a tree | "like Forest, but AI-native" |
| iCloud totals across devices | "across my devices" |

## Buckets

Every second of foreground use falls in one bucket:

- **productive**: work tools (Xcode, Terminal, Notion, Linear, Mail, Figma, Claude, ChatGPT…).
- **neutral**: necessary but neither (Maps, Wallet, Settings, Phone, Calendar). Not counted.
- **procrastination**: feeds, games, video, news (TikTok, Reels, Netflix, Reddit…).
- **ambiguous**: apps that serve both (Instagram, YouTube, X, LinkedIn, Telegram, WhatsApp,
  Threads, Substack). The four signals below decide each session.

## The four signals for ambiguous use

1. **Intent check (iPhone).** Ambiguous apps sit behind a Screen Time shield. It asks
   "Work or scroll?". *Work* unlocks the app for 15 minutes of use, counted as productive. *Scroll*
   unlocks 5 minutes, counted as procrastination. The pause itself cuts mindless opens.
2. **Context (Mac).** The Mac reads the front window title and the browser URL. Rules settle
   the clear cases: `instagram.com/direct` is work, `instagram.com/reels` is not.
3. **AI verdict (Mac).** When no rule fits, Apple's on-device model judges the title and URL
   against the owner's goals. It is free and private, and nothing leaves the Mac. The verdict
   is cached per site and title for the day.
4. **Nightly review (both).** The three largest unclear sessions of the day are shown with the
   AI's guess. One tap per session: "work" or "waste". Each answer becomes a rule.

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

## Day

A day runs from 04:00 to 04:00 local time. Late-night scrolling belongs to the evening it
started in.

## Not in v1

- Cloud AI insights (weekly patterns, "your worst hour is 22:00"): v2, through the accounts
  hub on Haiku 5.5.
- Goals imported from Knut: v2.
- iPad, Android, web.
