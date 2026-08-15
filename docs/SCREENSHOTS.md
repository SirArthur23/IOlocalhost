# Screenshots checklist

The shots to grab for the README, the GitHub release, and the launch posts — in the order
they matter. Put the files in `docs/images/` with the filenames below, then uncomment the
hero `<img>` in the README.

## Before you start (5-minute setup for a clean-looking demo)

- **Stage a few good dev servers** so the **Development** group looks alive. E.g. start a
  Vite app and a `python3 -m http.server` from IO, and give them friendly labels
  ("Marketing site", "Docs preview"). Having 2–3 green dev servers reads much better than one.
- **Appearance:** capture in **Light mode** for the primary README hero (it reads well on
  GitHub's light theme). Optionally grab a Dark-mode variant too — the app supports both.
- **Window size:** resize to roughly **900 × 640**. Consistent size across shots looks tidy.
- **Tidy the frame:** collapse the noisy System/Application groups so the Development group is
  the star. Nothing confidential should be visible — folder paths appear in some rows, so use
  a demo folder if you'd rather not show real client paths.
- **Capture command:** `⌘⇧4` then **Space**, click the window → gives a clean shot **with the
  window shadow** on a transparent background (Retina @2x). Or use `⌘⇧5` for more control.

## The shots (in priority order)

| # | File | What to show | Used for |
|---|---|---|---|
| 1 | `hero.png` | Main window, **Running** selected: Development group expanded with 2–3 labeled green servers; Adobe/Docker/System groups collapsed below. The whole app in one glance. | README hero, social image |
| 2 | `detect.png` | **＋ New Server** with a folder chosen and the **Detected** panel showing (e.g. "Detected: Vite · pnpm", the exact command, and the `dev / build / preview` script chips). This is the standout feature — make it shine. | README features, LinkedIn |
| 3 | `logs.png` | A running server's **log console** open (terminal icon), showing live output and the running indicator. | README features |
| 4 | `favorites.png` | **Favorites** section with a couple of entries — running (green dot) with **Stop**, stopped with **Start**, and one showing **Set Up…**. | README, release notes |
| 5 | `safety.png` *(optional)* | The **confirm-before-stop** dialog when stopping a non-dev/System process — communicates the safety model. | Release notes |
| 6 | `ghost.png` *(optional)* | Ghost `ops/` detection: the **Detected** panel with `run_*` script chips and per-site ports. Great if you're targeting the Ghost crowd. | Ghost-audience posts |

## After capturing

1. Save into `docs/images/` with the names above.
2. In `README.md`, uncomment the hero `<img>` block (points at `docs/images/hero.png`).
3. Optionally add shots 2–4 inline in the README's **Features** section:
   ```markdown
   ### Start from a folder
   ![Project detection](docs/images/detect.png)
   ```
4. Attach `hero.png` (or a short GIF) to the GitHub release for a nice social preview.

## Optional: a short screen recording

A 10–15s clip — pick a folder → Detected panel → Create Server → logs stream → Stop — is the
single most convincing asset for social. Record with `⌘⇧5`, keep it under ~15s, and export
as an optimized GIF or MP4. Name it `demo.gif` / `demo.mp4` in `docs/images/`.
