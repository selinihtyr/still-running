# Still Running — Design

Date: 2026-07-27
Status: Approved

## Problem

Developer machines accumulate processes nobody meant to keep alive: an
automation browser left over from a tool run, containers from a project you
stopped working on yesterday, a booted simulator, a dev server whose terminal
you already closed. Each one is invisible in normal use. Together they burn a
core, hold gigabytes, and heat the machine — and the only symptom the user
notices is a hot laptop hours later.

Activity Monitor answers "what is using CPU right now". It does not answer
"which of these did I forget about, and is it safe to stop".

## What Still Running is

A macOS menu bar app that surfaces processes the user has forgotten about, and
stops them in one click. It only ever stops things. It never deletes anything,
so every action is reversible by restarting the thing.

Not a system monitor. It does not chart CPU history, read thermal sensors, or
compete with Stats/iStat Menus. Its output is a short list of decisions.

Requires no elevated permissions: no root, no Accessibility, no Full Disk
Access. Runs unsandboxed (it reads the process table and sends signals), so it
ships as a direct DMG download rather than through the App Store.

## Users

Developers on macOS who run containers, simulators, dev servers, and automation
browsers. English-only.

## Detection

### Sources

| Source | Mechanism |
| --- | --- |
| Process table | `libproc` (`proc_listpids`, `proc_pidinfo`) + `sysctl` `KERN_PROCARGS2` for arguments and `KERN_PROC` for tty/ppid |
| Containers | Docker Engine HTTP API over the unix socket (`/var/run/docker.sock`, `~/.orbstack/run/docker.sock`) |
| Simulators | `xcrun simctl list devices booted -j` |

No shelling out to `ps` or `docker`. `simctl` is the one exception; there is no
stable alternative interface.

### Detectors

Each detector is independent and answers one question: is this thing plausibly
forgotten?

| Detector | Signal |
| --- | --- |
| Isolated browser | `--user-data-dir` outside the default profile location, `--headless`, or `--remote-debugging-port` present in the argument vector |
| Container | Container running, with uptime and CPU/memory from the Engine API |
| Simulator | Booted, plus how long it has been booted |
| Dev server / watcher | Executable or argv matches a known set: node, bun, deno, vite, next, webpack, nodemon, metro, uvicorn, flask, rails, gradle daemon, watchman |
| Orphan | `ppid == 1`, no controlling tty, and not an application bundle |

### Thresholds

A detector match alone does not surface an item. It must also cross at least one
threshold:

- Running longer than the age threshold (default 2 hours), or
- Orphaned (parent is launchd and it is not a normal app), or
- Sustained CPU above 25% for at least 3 minutes, or
- Idle below 2% CPU for at least 30 minutes while holding more than 500 MB
  resident.

All four numbers are defaults, adjustable in settings.

CPU and memory are evaluated against a rolling ring buffer of roughly the last
five minutes, not a single instantaneous sample. This is what lets the UI say
"62% sustained for 3 minutes" instead of reacting to a spike, and it is the
difference between the app feeling accurate and feeling noisy.

### Panel structure

Two lists:

- **Still running** — detector matches over threshold. Each has a stop action.
- **Also hot** — anything else near the top of CPU. Informational only, with no
  action button, so the app never invites the user to kill WindowServer.

## Safety

This app sends signals to processes. Safety is a correctness requirement, not a
polish item.

**Never-touch list.** Excluded from actions entirely: `kernel_task`,
`WindowServer`, `launchd`, `loginwindow`, `Finder`, any pid below 100, any
process not owned by the current uid, the app itself, and the user's
default-profile browser. A browser process counts as default-profile — and so
is never offered — when its argument vector has no `--user-data-dir`, or when
that flag points inside the standard profile location for that browser. Only
isolated or automation profiles are ever offered; the user's own tabs are never
a target.

**Graceful first.** Stopping means SIGTERM (or `docker stop` with its timeout,
or `simctl shutdown`). After a five-second wait, if the process is still alive,
a separate and explicitly labelled "Force quit" button appears. The app never
sends SIGKILL on the first click and never sends it silently.

**Keep this.** Any item can be permanently excluded in one click. The exclusion
matches a stable identity — executable path plus a normalised argument
signature, container name, or simulator UDID — not a pid.

**Confirmation.** Individual stops are one click, because they are reversible.
The bulk "Stop all" action asks first.

## Architecture

Swift 6, SwiftUI, macOS 26+. `MenuBarExtra` in window style. `LSUIElement`, so
there is no Dock icon.

```
still-running/
  StillRunning/            App target: MenuBarExtra, panel, settings
  Packages/
    ProcessKit/            libproc + sysctl wrapper -> Snapshot (pure, testable)
    Detectors/             Detector rules, threshold evaluation
    Actions/               Stopper protocol: Signal / Docker / Simctl
    DockerClient/          HTTP over unix socket, Docker + OrbStack
  StillRunningTests/
```

Local Swift packages rather than one app target, so each unit is testable
without launching the app and no file grows into a catch-all.

### Data flow

```
Sampler (5s while panel open, 60s while closed)
  -> ProcessKit.snapshot()
  -> History (ring buffer, ~5 min)
  -> DetectorEngine.evaluate(snapshot, history, rules)
  -> [Finding]
  -> Store -> panel + menu bar badge
```

### Key types

- `Snapshot` — one sample of the whole machine: processes, containers,
  simulators. Serialisable, which is what makes fixture-based testing possible.
- `Detector` — `func findings(in: Snapshot, history: History) -> [Finding]`.
- `Finding` — stable `identity`, title, subtitle, metrics, severity, optional
  action.
- `Stopper` — protocol. Real implementations send signals, call the Docker API,
  or invoke `simctl`. Tests inject fakes, so the test suite never touches the
  live system.

### Menu bar presentation

Badge shows the count of findings, and shows nothing when the machine is clean.
The icon has a distinct clean state and attention state.

### Notifications

One notification type, opt-in and off by default, rate-limited: something has
been running far past the threshold. This exists because the original failure
mode was not noticing for eighteen hours.

## Testing

Detectors and thresholds are pure functions over a `Snapshot`, so they are
tested against recorded fixtures. A debug command records the current machine
state to JSON for use as a regression fixture.

The tests that matter:

- A leftover automation browser in a fixture is flagged.
- The user's default-profile browser in the same fixture is not flagged.
- Every never-touch entry is never passed to a `Stopper`, under any rule
  configuration.
- Threshold logic uses sustained history, not a single sample.
- Stop actions call the correct mechanism per finding type.

## Publishing

`github.com/selinihtyr/still-running`, MIT. README with light and dark
screenshots. CI builds and tests on `macos-latest`. The release workflow
produces a DMG.

Signing starts ad-hoc, with README instructions to right-click and Open. Moving
to a Developer ID and notarisation is a release-time decision, not a build-time
one, and does not affect the code.

## Out of scope for v1

Disk cleanup (DerivedData, caches, dangling images), thermal and fan sensors,
history charts, Homebrew cask, localisation.
