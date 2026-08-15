# Contributing to IO: localhost

Thanks for your interest! This is a small, dependency-free SwiftUI macOS app, so getting
started is quick.

## Getting set up

- **Requirements:** macOS 14+ and Xcode 15+.
- Open `LocalhostIO.xcodeproj` and press ⌘R. If prompted about signing, choose
  *Sign to Run Locally* — no Apple Developer account is needed to build and run locally.
- There are no third-party dependencies and no package manager to bootstrap.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized.

## How the app is structured (quick map)

| Area | File |
|---|---|
| App entry + quit handling | `LocalhostIOApp.swift` |
| UI | `ContentView.swift`, `RunningServersView.swift`, `SavedServersView.swift`, `NewServerView.swift`, `ServerRowView.swift` |
| State | `AppState.swift` |
| Domain types, detection, classification | `Models.swift` |
| Port scanning | `PortScanner.swift` |
| Process control / argv recovery | `ProcessManager.swift` |
| Launching (process groups + logs) | `ServerLauncher.swift` |
| Persistence | `Store.swift` |

## Good first contributions

- **Teach the project detector a new framework.** Extend `ProjectDetector.analyze` in
  `Models.swift`. The unit of work is a `ProjectAnalysis` (summary, icon, method or exact
  command, port). Node frameworks are keyed off `package.json` dependencies + the lockfile.
- **Add a vendor to the smart-group classifier.** `ProcessClassifier` in `Models.swift` uses
  a hand-maintained token table for app vendors, dev runtimes, and system daemons. Adding a
  vendor is usually a one-line change.
- **Improve an empty state, label, or accessibility affordance.**

## Testing

Most of the interesting logic is pure and can be exercised without the GUI. During
development, detection/scanning/launch logic has been validated by compiling the relevant
`.swift` files into a tiny CLI and running them, e.g.:

```bash
xcrun --sdk macosx swiftc -O LocalhostIO/Models.swift LocalhostIO/ProcessManager.swift \
  LocalhostIO/PortScanner.swift your_main.swift -o /tmp/probe && /tmp/probe
```

If you touch detection, classification, port scanning, or the launcher, please include a
short note in the PR describing how you verified it.

Before opening a PR, make sure the whole thing still type-checks:

```bash
xcrun --sdk macosx swiftc -typecheck -target arm64-apple-macos14.0 LocalhostIO/*.swift
```

## Style

- Match the surrounding code: clear names, small focused types, comments only where intent
  isn't obvious.
- Keep the app dependency-free and sandbox-free by necessity (it shells out to `lsof`/`kill`
  and spawns your project commands) — please don't add third-party dependencies without
  discussion.

## Pull requests

1. Fork and branch from `main`.
2. Keep PRs focused; describe the change and how you tested it.
3. By contributing, you agree your contributions are licensed under the project's
   [MIT License](LICENSE).

## Reporting bugs

Open an issue with:
- what you did, what you expected, what happened;
- for launch problems, the **log console** output (the terminal icon on a server row) — it
  usually contains the exact error;
- your macOS version and the project type/command involved.
