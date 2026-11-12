# Pick 01 — note

The owner's answer, verbatim: "1 + 3" (12 Nov 2026). It names two options: 1 (`guard-my-list`)
and 3 (`block-work-hours`). `teyla design pick` records one option id, so `pick.yaml` holds
`guard-my-list` as the base and this note records `block-work-hours` as the addition.

## How the two combine — confirmed 12 Nov 2026

The owner's words, verbatim:

> "Я бы сделал это настраиваемым - чтобы я мог выбрать, для чего ставить блок, а для чего паузу.
> И чтобы я мог переключить, например, инстаграм из procrastination в work mode - и время уже
> засчитывалось бы за рабочее. То есть я вижу это как иконку в controls menu - чтобы я визуально
> по изображению и цветам мог понять, какой сейчас мод стоит, и мог его переключить. И чтобы ты
> меня уведомлял когда мы переходим из work в procrastination mode"

What his words settle:

1. **Per place, he chooses block or pause** (confirmed). One list of up to three waste places
   with the 30-minute budget. Each place has one mode:
   - **pause**: the 5-second pause all day; Close is the big button, "Open for 5 minutes" the
     small one;
   - **block in work hours**: the place does not open inside the hours he sets; unlocking is a
     deliberate step; outside those hours it pauses.
2. **He can switch a place from procrastination to work** (his example: Instagram). From then
   on its time counts as work.
3. **One icon in the controls menu** shows, by image and colour, which mode is on now, and
   switches it.
4. **Vago notifies him when he moves from work into procrastination.**

## Defaults for the parts his words leave open (the director's reading, not his words)

- "Controls menu": Vago's menu-bar icon on the Mac, plus a Control Center control. macOS 26
  supports third-party controls (`ControlWidget`, WidgetKit, macOS 26.0 in the SDK).
- "Which mode is on now" is a global state (work / procrastination, neutral when neither),
  derived from the place in front.
- The notification is a statement, never a question: the locked rule "no 'are you working?'
  question during the day" stands. It fires after about a minute in a waste place, at most once
  per drift, and never for a place the pause already guards (the pause is the signal).
- Decisions 05 (moment of drift) and 09 (glance surfaces) take his words as input; see
  `input.md` in each folder.

## The switch is a plain toggle — confirmed 12 Nov 2026

The owner's words, verbatim:

> "Надолго ли переключение - мне кажется, что я в инстаграме могу и прокрастинировать, и
> работать с разницей в 15 мин - и это должен быть просто тумблер переключения"

- One tap on the mode icon flips the place in front between work and procrastination, both
  directions. No duration, no confirmation.
- Time counts by the toggle's state at each second, from the moment he flips it. The same place
  can be work now and procrastination fifteen minutes later.
- While a place is toggled to work, its pause or block does not fire and no drift notification is
  sent for it; flipping back restores them.

Not said by him, so the two variants differ here: variant A keeps the place as he last set it
until he flips it back; variant B returns the place to its list mode when he leaves it or at the
start of the next day.

The rule proposal written by the pick (`d373f0e0-….json`) describes option 1 only and is
unconfirmed.
