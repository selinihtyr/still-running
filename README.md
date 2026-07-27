<h1 align="center">Still Running</h1>

<p align="center">
  <strong>The containers, simulators, and stray processes you forgot are still running.</strong><br>
  A small macOS menu bar app that finds them and stops them in one click.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26 or newer">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Why

A laptop got hot. The cause turned out to be a headless Chrome, started by a
tool, running for eighteen hours on a throwaway profile, burning most of a core
the whole time. Nothing in Activity Monitor said "you forgot about this one" —
it just showed a browser near the top of a list, next to the browser actually
in use.

Activity Monitor answers *what is using CPU right now*. Still Running answers
*which of these did I forget about, and is it safe to stop*.

## What it finds

| | Signal |
| --- | --- |
| **Automation browsers** | `--user-data-dir` outside the normal profile, `--headless`, or a remote-debugging port |
| **Containers** | Docker or OrbStack containers, aged by when the current run started |
| **Simulators** | Booted simulators, aged from the device's own `launchd_sim` |
| **Dev servers** | node, bun, deno, vite, next, webpack, metro, uvicorn, gradle daemons, watchman |
| **Orphans** | Reparented to launchd with no controlling terminal — and not a service launchd manages on purpose |

Something appears only once it also crosses a threshold: older than two hours,
or orphaned, or above 25% CPU sustained for three minutes, or idle for half an
hour while holding more than 500 MB. All four are adjustable.

Rates come from a rolling five-minute history rather than a single reading, so
a brief spike never puts anything on the list.

## What it will never do

- **Never deletes anything.** It stops things. Every action is undone by starting
  the thing again.
- **Never touches your browser's own tabs.** Only isolated and automation
  profiles are ever offered. A browser on its normal profile is refused at two
  separate layers.
- **Never force quits on its own.** The first click sends SIGTERM. Force quit is
  a second, separate, explicitly labelled click that appears only if the first
  one was ignored.
- **Never asks for privileges.** No root, no Accessibility, no Full Disk Access,
  no login item. It reads the process table, which any process may do.

Processes it cannot vouch for appear under "Also busy, but yours" — visible, but
with no button next to them.

## Install

Download the DMG from [Releases](../../releases/latest), drag **Still Running**
to Applications, then **right-click it and choose Open** the first time. The
build is signed ad-hoc rather than notarised, so Gatekeeper asks once.

It lives in the menu bar. There is no Dock icon and no window.

## Build from source

```bash
swift test          # 116 tests, no network, no side effects
./scripts/bundle.sh # produces build/Still Running.app
```

Requires Xcode 26 and macOS 26.

## How it works

`ProcessKit` samples the process table through `sysctl` and `libproc` into a
serialisable `Snapshot`. `DockerClient` adds containers by speaking HTTP over
the Docker unix socket, and `SimulatorSource` adds simulators through `simctl`.
`Detectors` turns a snapshot plus rolling history into findings, and `Actions`
stops them behind a safety guard that no other code path can bypass.

Because a snapshot is just data, every rule is tested against recorded fixtures
of real machine states — including the one where the user's own Chrome must not
be flagged while an automation Chrome beside it must be.

## License

MIT.
