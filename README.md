<div align="center">

# IO: localhost

**A native macOS app for seeing, starting, and stopping your local dev servers.**

Every process listening on a `localhost` port, grouped and labeled — plus one-click
start/stop for your own projects, live logs, favorites, and smart project detection.

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg)
![UI: SwiftUI](https://img.shields.io/badge/UI-SwiftUI-1575F9.svg)
![No dependencies](https://img.shields.io/badge/dependencies-none-success.svg)
![Latest release](https://img.shields.io/github/v/release/SirArthur23/IOlocalhost?sort=semver)
![Downloads](https://img.shields.io/github/downloads/SirArthur23/IOlocalhost/total)
![Stars](https://img.shields.io/github/stars/SirArthur23/IOlocalhost?style=social)

<!-- Add the hero screenshot here once captured (see docs/SCREENSHOTS.md):
<img src="docs/images/hero.png" alt="IO: localhost showing local servers grouped by application" width="820">
-->

</div>

---

## Why

If you do web development, you have servers running all over `localhost` — a Vite app
on 5173, a Django API on 8000, three Ghost sites, Docker publishing half a dozen ports —
and no easy way to see what's what. `lsof -i` in a terminal tells you *something is on
3000*, but not which project, whether it's safe to kill, or how to start it again.

**IO: localhost** turns that into a clean desktop window:

- **See everything** listening on a local port, auto-grouped by app (Adobe, Docker, your
  dev servers…) and color-coded so you don't kill a system process by accident.
- **Start & stop your own servers** with one click — it detects the project type and the
  right command for you.
- **Favorites & recents** so the projects you touch daily are one click away.
- **Live logs** for anything you launch, streamed into the app and saved to disk.

## Features

- 🔎 **Live port list** — every listening TCP port, refreshed automatically.
- 🧠 **Smart groups & safety colors** — ports are grouped by application and tagged
  *Development / Application / System / Other*. Stopping a non-dev process asks first.
- 🏷️ **Custom labels** — give any port a human name ("Marketing site", "Staging API").
- ⭐ **Favorites & recents** — pin the servers you use most; recents remember how to relaunch.
- ▶️ **Start from a folder** — pick a folder and IO detects the framework **and** package
  manager, recommending the exact command (`pnpm dev`, `python3 manage.py runserver`, …).
- 📜 **Live logs** — combined stdout/stderr in a console, persisted across restarts.
- 🧩 **Command lines** — see the full command behind any running port, with copy.
- 🛑 **Clean stop** — servers you launch run in their own process group, so stopping
  takes their child processes with them.

### Auto-detected project types

Node (Next.js, Nuxt, Vite, CRA, Angular, Remix, Gatsby, Astro, SvelteKit, Vue — with
npm/yarn/pnpm/bun), **Ghost** (Ghost-CLI installs and custom `ops/` start-scripts),
Python (Django, Flask), PHP (Laravel), Ruby (Rails/Rack), Go, Rust, Hugo, Jekyll, and
plain static sites. Anything else → a prefilled, editable custom command.

## Requirements

- macOS 14 (Sonoma) or later
- Whatever runtimes your projects need (Node, Python, Ghost-CLI, …) on your `PATH`

## Install

> **Note:** IO: localhost is a developer tool that runs `lsof`, `kill`, and your project
> start commands on your behalf. It runs **outside the macOS sandbox** by design and does
> not collect or transmit any data.

### From a release build
1. Download the latest `IO-localhost.zip` from the [Releases](https://github.com/SirArthur23/IOlocalhost/releases) page.
2. Move **IO: localhost.app** to your Applications folder.
3. Launch it. *(If macOS warns about an unidentified developer, right-click the app →
   **Open** → **Open**. See [the manual](MANUAL.md#first-launch--gatekeeper).)*

### From source
Open `LocalhostIO.xcodeproj` in Xcode 15+ and press ⌘R. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the codebase layout.

## Quick start

1. Open the app — the **Running** list shows everything currently listening.
2. Click **＋ New Server**, choose a project folder, and IO detects how to start it.
3. Press **Create Server** — it launches, streams logs, and appears in the list.
4. Star it to keep it in **Favorites** for next time.

Full walkthrough: **[User Manual →](MANUAL.md)**

## Privacy & security

IO: localhost runs entirely on your machine. It has **no network features, no telemetry,
and no analytics**. It reads the list of local listening ports via `lsof`, and it runs the
start/stop commands you configure. Because it manages other processes, it is intentionally
not sandboxed.

## License

See [LICENSE](LICENSE).

## Contributing

Issues and pull requests are welcome. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for
how the app is put together.
