# Changelog

What changed, in the words of someone using it rather than someone writing it.

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
