# Changelog

## v1.0.0 — unreleased

First public release.

### Features
- Live list of every process listening on a local TCP port, auto-refreshing.
- Smart groups by application (Adobe, Docker, Development…) with safety colors and
  confirm-before-stop for non-dev processes.
- Custom per-port labels; Favorites and Recent sections.
- Start a server from a folder with project auto-detection: Node (Next/Nuxt/Vite/CRA/
  Angular/Remix/Gatsby/Astro/SvelteKit/Vue with npm/yarn/pnpm/bun), Ghost (Ghost-CLI and
  custom `ops/` start-scripts), Python (Django/Flask), PHP (Laravel), Ruby, Go, Rust, Hugo,
  Jekyll, and static sites.
- Launched servers run in their own process group; stopping takes their children with them.
- Live, persisted per-server logs.
- Full command line surfaced for every running port, with copy.
- Restartable favorites: captures working directory + command when recoverable; a Set Up
  sheet configures the rest.
- Port-in-use warnings in the New Server / Set Up forms.

### Pre-release polish
- Confirm-on-quit when servers IO launched are still running (stop all / leave running).
- VoiceOver labels on icon-only controls.
- Backgrounding (`nohup … &`) start scripts are de-emphasized in favor of foreground
  `run_*` variants that IO can manage.
- "Exited on launch — view log" badge when a just-started server dies quickly.
- **Project-aware labels & favorites.** A saved label/favorite is now matched to the actual
  project (by working directory), not just the port number — so a different app running on a
  reused port (e.g. 3000) no longer inherits the wrong name or star, and Stop can't kill an
  unrelated process that merely shares the port.
