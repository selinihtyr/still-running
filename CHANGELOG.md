# Changelog

What changed, in the words of someone using it rather than someone writing it.

## [0.5.0] — 2026-07-29

### It says what is keeping this Mac awake

The battery is flat by morning, the fans ran inside a closed bag, and macOS
will not tell you why. The answer is always a process holding a promise that
the machine will not sleep — a `caffeinate` a script never released, a tab
still playing audio, a video wake lock nobody took back — and the only place
it is written down is a table of assertions nobody reads.

They are named now, with the holder's own words for why: "Playing audio",
"Video Wake Lock", "caffeinate command-line tool", and how long it has been
going on. If everything else is quiet, the first line of the panel says it
outright.

**Only some of it is offered up.** A `caffeinate` nobody released is exactly a
thing to stop, so it gets a row with a button. An app is named and left alone:
quitting your browser because it is playing audio would be a worse bug than the
one this exists to fix. Neither is anything launchd manages, because a button
that stops something launchd starts again is a button that does nothing twice.

Things that release themselves are never mentioned. Tools wrap commands in
`caffeinate -t 300` by the dozen and not one of them is something anyone
forgot. Nor is macOS talking to itself: `sharingd` holds one for Handoff and
`powerd` holds one whenever the display is on, forever, and neither can be
stopped by anyone.

### It tells you a new version is out

Until now the only place a release was mentioned was a strip in the panel —
which reaches exactly the people who open the panel. This app has no window and
no Dock icon, so months can pass without anyone opening anything, and the whole
point of noticing a release is reaching the people who are not looking. There
is now one notification per version, ever. Asking for the check yourself in
Settings does not produce one, because the answer is already on the screen; it
still counts as said, so nothing turns up later about the same version. The
switch that governs it is the one for checking at all.

### A shell burning a core is no longer filed under "core binaries"

`/bin` and `/usr/bin` were skipped when looking for orphans, and rightly: they
hold Apple's own tools, and the shell a closed terminal leaves behind is
reparented to launchd, where nobody wants to be told about it. But they also
hold your own tools. Two `/bin/sh -c 'while :; do :; done'`, orphaned by an
interrupted test run, pinned a core each on this machine for eight minutes, and
the app that exists to notice exactly that said nothing at all.

Those directories are still skipped while what is in them is quiet. They are
not skipped when something there has been burning a core for minutes. macOS's
own helpers stay out either way, so Spotlight indexing does not become an
alarm.

### The panel stopped doing its thinking on the main thread

Working out what is running is about twenty milliseconds of matching across
every process on the machine, and it was happening on the thread drawing the
window, every five seconds the panel was open. It now happens off it. Along the
way a snapshot learned to find a process by pid without searching the whole
table, which is most of the cost of every rate the app calculates.

### Fixed

- Two processes started the same way — this machine had two `caffeinate`s at
  once — could produce two rows carrying one identity, which is a list that
  cannot be keyed and an exclusion that matches the wrong thing. They are one
  row now, and stopping it stops both.
- Dismissing a row with **Never list this again** could move it to the
  informational list below instead of taking it away.
- A refresh that took longer than the one after it could land its older answer
  on top of the newer one. Stopping something starts its own refresh, so two
  really are in flight whenever anyone clicks.

## [0.4.2] — 2026-07-29

### A night's sleep is not eight quiet hours

A percentage measured across a sleeping laptop is not a percentage. Rates were
divided by time on the wall, and this machine spent four of its last eleven
hours asleep — so anything left running overnight had its CPU divided by the
nap and read as a few percent by morning. Worse, the rule that decides
something has been busy for a while looks for the quietest stretch it can find,
and the nap was always the quietest: on the one night it mattered, the app had
nothing to say. Which is the whole job.

Sleep counted as idle time, too. Shut the lid for eight hours and every large
process woke up looking abandoned — a false alarm delivered at exactly the
moment you are deciding whether to trust any of this.

Rates, and the windows they are measured over, now run on the time the machine
was actually awake. An age still runs on the wall clock, because you did start
it five hours ago.

### Opening the panel no longer catches a process mid-blink

Opening the panel takes a sample straight away, and that one can land a
fraction of a second after the sample the timer just took. Whatever a process
happened to be doing in that fraction became the percentage on the row — and a
browser, whose helpers are counted as one thing, reads in the hundreds that
way. Measured here: a busy loop read 98% across a six-hundred-millisecond gap
and 10% measured properly. A gap too short to mean anything is now widened
until it means something.

## [0.4.1] — 2026-07-28

### The footer says something worth reading

It used to count seconds since the last check, forever. A number that climbs
and never means anything, in the one line of the panel that could be telling
you something. It now says which version you are on and whether that is the
newest one — and turns blue when a newer release is waiting.

The answer is also remembered between launches, so quitting and reopening no
longer forgets that an update exists until the next day's check comes round.

### Fixed

- `node -e "…"` was titled with its own source code, so a one-line server read
  as `node · require('http').createServer((q,s)=>s.end('ok')).listen(4599);`.
  There is no script file to name in that case, so it is just `node` now.
- The live test suite failed rather than skipped when no container runtime was
  running. A red test for a daemon you have chosen not to run reads as a broken
  app.

## [0.4.0] — 2026-07-28

### It survives a restart

Until now, restarting your Mac was the end of it. You would reboot, the menu bar
would come back without the ring, and nothing would be watching — which is a
strange failure for an app whose entire job is noticing things you left running
for hours. Reported by the first person to restart their machine.

It now registers itself as a login item, once, and **Settings › Start at login**
turns it off. If macOS is blocking it, the switch says so and points at the
System Settings pane that can let it back in.

### It tells you when there is a new version

The panel shows a strip when a newer release exists, and **Update** opens a
Terminal window that runs the same two commands the README has always given you:
`git pull` and `./scripts/install.sh`. In a Terminal rather than silently in the
background, because a build takes a minute and you should be able to watch it —
and see it fail.

If the checkout it was built from has moved or gone, it opens the release page
instead of running an installer from a path that may no longer hold one.

This is the only thing that leaves your machine: one request a day to GitHub's
public releases API, asking for a version number. Nothing about you is sent, and
**Settings › Check for updates** turns it off entirely — with it off, the app
never touches the network at all.

### Settings survive an upgrade

Adding a setting used to throw away every choice you had made. A settings file
written by an older version has no key for a setting that did not exist yet, and
the decoder treated that as a corrupt file and started over from the defaults.
Each field now falls back to its own default, so this one is the last release
that could have done it to you.

## [0.3.0] — 2026-07-28

### It runs on macOS 14 instead of macOS 26

The floor was macOS 26 for one reason: a single `Mutex` from the Synchronization
framework, which needs macOS 15. Swapping it for a lock and a box moved the
requirement down two whole releases — from a version released weeks ago to one
from 2023. Building it now needs Xcode 16 rather than Xcode 26 as well.

Nothing else in the app needed anything newer. It was excluding almost everyone
by accident.

It is developed and used daily on macOS 26, and it builds with its tests passing
for macOS 14, but nobody has run it there yet. If something looks wrong on an
older version, please open an issue.

## [0.2.0] — 2026-07-28

### Rows explain themselves

Click a row and it opens. It says what the thing is in plain words, shows the
command that started it, and links to where it lives on disk. A profile path
like `/tmp/claude-cdp-prof` is an identifier, not an explanation, and it took
someone saying *I don't understand what this is* for that to be obvious.

Where the profile path or the command line names a tool it recognises — Claude
Code, Playwright, Puppeteer, Selenium, Cypress, ChromeDriver, Lighthouse — it
says which one started the browser. When it cannot tell, it says nothing rather
than guessing.

### It finds more

- **Android emulators**, named after the device (`Pixel 7 API 34`) and grouped
  with their helper processes. They hold more memory than almost anything else
  people leave running, and Android Studio never mentions one that has been up
  since yesterday.
- **Tunnels** — cloudflared, ngrok and the rest — with what they are publishing.
  Listed on age alone, and always urgent: everything else here wastes a core,
  but a forgotten tunnel is still exposing a port on your machine to the
  internet.
- **Containers from Colima, Podman and Rancher**, alongside Docker and OrbStack.
  They all speak the same API from different sockets.

### It nags less

- A dev server that has done real work in the last ten minutes is no longer
  listed. Age alone was flagging the server you are typing against.
- "Busy, but yours" now shows only processes you own, never the insides of a
  simulator that is already one row, and only load that has held for half a
  minute. It was listing a macOS diagnostics daemon and four simulator
  internals, then dropping them again a moment later.
- Still Running no longer reports itself.

### Fixed

- **CPU percentages were about forty times too small.** `proc_taskinfo` reports
  Mach absolute time units rather than nanoseconds, so a process pinning a core
  read as 2%. Everything built on CPU quietly did nothing: the sustained-load
  threshold never fired and nothing was ever marked urgent.
- The footer icons drifted, because a spinning refresh glyph changed its
  bounding box and a hundred-millisecond sample always interrupted the
  animation, leaving it at whatever angle it had reached.
- The panel opened with a header, a button and no rows at all when there were
  more than six findings.
- Opening the panel now looks straight away instead of waiting out the
  minute-long sleep it started while closed.
- Stopping something no longer leaves the row sitting there for the ten seconds
  Docker spends on a container's grace period.

### Also

- The menu bar icon stays monochrome, the way menu bar icons do. It carries the
  size of the waste through its glyph — a ring, a dotted ring, a flame — and
  the number beside it becomes a percentage once that is the more useful figure.
- The panel reports how hard macOS says the machine is being pushed, and says
  nothing while it is comfortable.
- Settings gained shorter thresholds and a button that sends a test
  notification, then tells you exactly what macOS allows — including whether
  sound is switched off for the app, which macOS keeps as a separate switch.

## [0.1.0] — 2026-07-27

First release.

Finds the containers, simulators, dev servers, automation browsers and orphaned
processes you forgot were running, and stops them from the menu bar.

- Nothing is ever deleted. Stopping a container or simulator can be undone for
  two minutes; stopping a process waits out a three second countdown you can
  cancel, because a signal cannot be recalled.
- Your own browser's tabs are never offered. That is refused in two separate
  places, and a test targets the real browser on a live machine and asserts it
  survives.
- No root, no Accessibility, no Full Disk Access, no login item, no network.
- Installed by building it: there is no notarised download, so Gatekeeper never
  gets an opinion.
