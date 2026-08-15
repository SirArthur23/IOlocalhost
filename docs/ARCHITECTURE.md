# Architecture

IO: localhost is a small SwiftUI macOS app (no external dependencies). It intentionally runs
**without the App Sandbox** because it shells out to `lsof`, `kill`, and your project's start
commands, and inspects other processes.

## Source layout (`LocalhostIO/`)

| File | Responsibility |
|---|---|
| `LocalhostIOApp.swift` | `@main` app entry, ⌘R refresh command |
| `ContentView.swift` | Sidebar + detail split view, New Server CTA, backgrounds |
| `RunningServersView.swift` | Grouped, collapsible live port list |
| `SavedServersView.swift` | Favorites / Recent lists |
| `NewServerView.swift` | New Server form, `DetectionPanel`, `ConfigureServerView` (Set Up), `PortInUseNotice` |
| `ServerRowView.swift` | Row views for running & saved servers, `LogConsoleView` |
| `AppState.swift` | `@MainActor ObservableObject` — the single source of truth |
| `Models.swift` | Data types, `ProjectDetector.analyze`, `ProcessClassifier` |
| `PortScanner.swift` | Parses `lsof` + batched `ps` into `RunningServer`s |
| `ProcessManager.swift` | `Shell` helper, `kill`, `KERN_PROCARGS2` argv recovery, cwd lookup |
| `ServerLauncher.swift` | `ServerProcess` (`posix_spawn` in a new process group) + launcher |
| `Store.swift` | JSON persistence for saved servers + `LogStore` for logs |

## Key mechanisms

- **Discovery**: `lsof -nP +c0 -iTCP -sTCP:LISTEN`, plus one `ps -axww` for full command
  lines. Results are grouped/classified by `ProcessClassifier`.
- **Launching**: `ServerProcess` uses `posix_spawn` with `POSIX_SPAWN_SETPGROUP` so each
  server is its own process-group leader; stopping sends `SIGTERM`/`SIGKILL` to the whole
  group. Combined stdout/stderr is piped back and streamed to the UI + `LogStore`.
- **Detection**: `ProjectDetector.analyze` returns a `ProjectAnalysis` (summary, icon,
  method or exact command, port, package manager, scripts). Node projects read the lockfile
  for the package manager; `ops/` shell scripts are detected and offered as chips.
- **Relaunch capture**: favoriting a discovered server captures its cwd (`lsof -d cwd`) and
  real argv (`sysctl(KERN_PROCARGS2)`). Note that processes which rewrite their own argv
  (Node/Next/Vite) can't be recovered — those fall back to the Set Up sheet.

## Persistence

`~/Library/Application Support/LocalhostIO/`
- `servers.json` — saved servers (labels, favorites, launch config)
- `logs/<id>.log` — per-server console logs

## Building & signing

- Deployment target: macOS 14. No third-party dependencies.
- Local runs use "Sign to Run Locally". For distribution, enable Hardened Runtime, sign
  with a Developer ID Application certificate, and notarize. See `docs/RELEASE.md`.
