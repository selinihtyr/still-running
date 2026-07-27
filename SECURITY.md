# Security

Still Running sends signals to processes and stops containers, so it is worth
being precise about what it can and cannot do.

## What it has access to

- **Reads** the process table (`sysctl`, `libproc`), the Docker socket, and
  `simctl` output. All of this is readable by any process running as you.
- **Writes** nothing to disk except its own preferences.
- **Sends** `SIGTERM`, and `SIGKILL` only after an explicit second action by
  the user.
- **Talks** to no network service. There is no telemetry, no update check, no
  account, and no outbound connection of any kind. The only socket it opens is
  the local Docker one.

It runs unsandboxed, because reading other processes requires it. It needs no
root, no Accessibility, no Full Disk Access, and installs no login item or
helper daemon.

## What it refuses to touch

Enforced in `Sources/Actions/SafetyGuard.swift`, on every path that could send
a signal:

- any process below pid 100
- any process owned by another user
- a hard-coded list of session-critical processes (`WindowServer`, `launchd`,
  `loginwindow`, `Finder`, and others)
- itself
- a browser running on its normal profile — only isolated and automation
  profiles are ever offered

The guard runs after detection and repeats checks the detectors already make,
deliberately: a bug in a detector must not be able to end your session. There
are tests that assert every one of these, including one that targets the real
browser on a live machine and asserts it is refused and still alive afterwards.

## Reporting a vulnerability

Open an issue at
https://github.com/selinihtyr/still-running/issues, or if you would rather not
discuss it in public, use GitHub's private reporting under the Security tab.

Please include the macOS version and, if it involves detection, the output of

```bash
swift test --filter detectsSomethingSensibleOnTheRealMachine
```

which prints what the app sees on your machine without changing anything.

## Verifying what you run

There is no notarised download to trust. You clone the repository and build it,
so what runs on your machine is what you can read in the repository:

```bash
git clone https://github.com/selinihtyr/still-running
cd still-running && swift test && ./scripts/install.sh
```
