# Changelog

What changed, in the words of someone using it rather than someone writing it.

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
