# GitHub release — v1.0.0

**Tag:** `v1.0.0`  ·  **Title:** `IO: localhost 1.0.0`  ·  **Attach:** `IO-localhost.zip`

---

## IO: localhost 1.0.0

A native macOS app for seeing, starting, and stopping your local dev servers — every
process listening on a `localhost` port, grouped and labeled, with one-click start/stop
and live logs for your own projects.

### Highlights
- 🔎 **Live port list** — everything listening on a local TCP port, auto-refreshing.
- 🧠 **Smart groups & safety colors** — ports grouped by app (Adobe, Docker, your dev
  servers…) and tagged Development / Application / System / Other. Stopping a non-dev
  process asks first, so you can't kill Docker or a system service by reflex.
- ▶️ **Start from a folder** — pick a folder and IO detects the framework **and** package
  manager, recommending the exact command (`pnpm dev`, `python3 manage.py runserver`, …).
- ⭐ **Favorites & recents** — pin the projects you use daily; recents remember how to relaunch.
- 📜 **Live logs** — combined stdout/stderr in a console, saved across restarts.
- 🏷️ **Custom labels** and 🧩 **full command lines** for every running port.
- 🛑 **Clean stop** — launched servers run in their own process group, so stopping takes
  their child processes with them.

### Detected project types
Node (Next.js, Nuxt, Vite, CRA, Angular, Remix, Gatsby, Astro, SvelteKit, Vue — with
npm/yarn/pnpm/bun), **Ghost** (Ghost-CLI installs and custom `ops/` start-scripts), Python
(Django, Flask), PHP (Laravel), Ruby, Go, Rust, Hugo, Jekyll, and static sites.

### Requirements
- macOS 14 (Sonoma) or later
- The runtimes your projects need (Node, Python, Ghost-CLI…) on your `PATH`

### Install
1. Download **`IO-localhost.zip`** below and move **IO: localhost.app** to Applications.
2. **First launch** (this build isn't notarized yet): open **System Settings → Privacy &
   Security**, find the note about IO: localhost, and click **Open Anyway**. On older macOS,
   right-click the app → **Open** → **Open**.

### Privacy
Runs entirely on your machine. No network features, no telemetry, no analytics. It reads
local listening ports via `lsof` and runs the start/stop commands you configure; because it
manages other processes, it is intentionally not sandboxed.

---

_Full manual: [MANUAL.md](../MANUAL.md) · Source & architecture: [docs/ARCHITECTURE.md](ARCHITECTURE.md)_
