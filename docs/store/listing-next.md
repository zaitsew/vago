# App Store listing draft: Vago: Focus Timer

Status: draft for the first store version. The app is not on sale (App Store Connect record
"Vago: Focus Timer", app id `6828551197`, SKU `vago`, bundle `com.zaitsew.vago`; docs/RELEASE.md).
A submission hold is in force, so nothing here is uploaded. Locale: English (U.S.) only; the repo
keeps no other locale. China mainland (`CHN`) stays excluded from availability.

## Name collision (4.3(a) Spam rule)

The plain name "Vago" was taken. Another app already uses the name: "Vago: vamos a turistear!"
(`com.elesteam.vago`), a travel app. Apple rejects a concept that matches an existing one, and the
two names are close. So:

- The subtitle and the first screenshot lead with what only this app does: it counts the minutes
  you lose to scrolling, against a limit that walks down to 30 minutes a day.
- Nothing in the listing mentions travel, tourism or maps.
- The review notes name the other app and say the two share only a name.

## Name (17 of 30)

Vago: Focus Timer

## Subtitle (29 of 30)

Count the scroll, grow a tree

## Promotional text (161 of 170)

Vago counts the minutes you lose to scrolling and shows them on a live timer. Your daily limit adapts and walks down to 30 minutes. Grow a tree when you focus.

## Description

Vago counts the minutes you lose to scrolling and the minutes you work, then shows both on a live timer.

A LIMIT THAT ADAPTS
Your daily limit starts at 60 minutes while Vago learns your habits for three days. It drops 5 minutes after every day you stay under it, rises 5 after a day well over it, and never goes below 30 minutes. The goal is at most 30 minutes of procrastination a day.

SMARTER THAN A BLOCK LIST
Social apps can be work. Pick your work apps, your scroll apps and the apps that are both. When you open one that is both, Vago asks "Work or scroll?" first. Work counts as productive. Scroll counts against your limit. The pause alone cuts mindless opens.

SEE IT LIVE
A widget and a Live Activity show today's scroll time against your limit. The face changes from happy to upset as you use it up: green, then yellow, then red.

GROW A TREE
Start a 25 or 50 minute focus session. A seedling grows into a tree while distracting apps stay paused. Scroll for more than a minute and it wilts, though the focus time so far still counts. The Garden shows this week's trees.

A REPORT OF YOUR DAYS
See where your time went, by day and by week, across the devices that share your iCloud.

PRIVATE
There is no Vago account and no Vago server. Your counts stay on your devices and in your own iCloud. Vago uses Apple's Screen Time controls, so it needs your permission to count app use.

SIRI AND SHORTCUTS
Ask how focused you are, check your limit, or start and stop a focus block by voice or from an automation.

Requires Screen Time access, and Share Across Devices turned on in Settings > Screen Time to see all your devices in the report.

## Keywords (96 of 100)

procrastination,screen time,focus,pomodoro,productivity,widget,habit,distraction,limit,work,tracker

## What's New (version 0.1.0)

First store version. Nothing has changed since the build the owner tested (0.1.0 (1), 29 October
2026); no feature PR has merged since. The line for a first release:

- First release: count scrolling against an adaptive daily limit, a "Work or scroll?" check, focus sessions that grow a tree, a widget and a Live Activity.

When the next version ships, replace this with one line per change merged after 0.1.0, from the PRs.

## Screenshots to retake

No screenshots are committed to this repo, so the whole set is new. Take them on a real iPhone
(Family Controls does nothing in the Simulator; docs/RELEASE.md). The newest UI commits are
`fe9671f` (Today, Focus, Report, Settings) and `c40ccde` (widget, Live Activity).

Order, with the first one leading with what only Vago does (see the name collision above):

1. Today: the scroll timer against the limit, with the mood face.
2. The "Work or scroll?" shield.
3. Focus: a tree growing, with the Garden.
4. Report: days and devices.
5. Lock Screen: the widget and the Live Activity.

Device classes: iPhone 6.9-inch only. The target is iPhone-only (`TARGETED_DEVICE_FAMILY` "1" in
`ios.yml`), so no iPad set. The Mac app is not in the store build and has no listing.

TODO(other locales): none kept today.
