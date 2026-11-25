# AGENT OVERVIEW — ccProxy (MTGO card pipeline, containerized)

**For future agents:** This repo packages the MTGO decklist → rendered card
PNGs → print PDF pipeline as OCI images (docker compose today; quadlet/NixOS
later). Read this file first, then:

- `AGENT_TODO.md` — open items, next up: **GitHub Actions build + registry**
- `AGENT_DOING.md` — nothing in flight; "NEXT SESSION, START HERE"
- `AGENT_DONE.md` — everything finished, with verification + commit hashes

The full build/smoke/A/B procedure and results are in `bringup.md` — it is
the source of truth for "how do we prove it works."

**Conventions:** one commit per change; commit trailer
`Co-Authored-By: Claude Code <noreply@anthropic.com>`. Keep these four
files current — they are the handoff when a context overflows. Don't delete
from DONE. User decisions are recorded with their date — treat them as
rulings, re-open only if the user does.

## Current status (2026-11-25) — read this first

**End-to-end tests are the active item.** The `cctest` e2e on `.216` (the
published `matthewddunlap/ccproxy-*:latest`) runs **GREEN end-to-end** —
render→pdf, offline/deterministic, cards byte-identical to the A/B baseline
(see AGENT_DONE, 2026-11-25). Left in flight (TODO #1): fix the `init`
card_images ownership bug (root cause of an app-PUT 500), add a repeatable
e2e script, commit + push (confirm push). Details: AGENT_DOING.md.

**Bringing-up is DONE and verified; all smokes + A/B green.** Both images
built and deployed alongside the old stack on `.216`; the flip (old conf's
`--url` → new stack) is the user's call, not done yet. **Build/publish is
LIVE (2026-11-24):** GitHub Actions builds both images and publishes them
PUBLIC to Docker Hub as `matthewddunlap/ccproxy-{cardconjurer,pipeline}`
(`:latest` + `<sha7>`); first green run #3, pulled + verified on .216 and
.217 — full record in AGENT_DONE.

State at a glance:
- Repo: `matthewddunlap/ccProxy` (public), main clean + pushed; images are
  published via GitHub Actions → Docker Hub (below).
- `ccproxy/cardconjurer:local` (4.62 GB): nginx + Card Conjurer app @ pinned
  SHA, 1 container / 4 listeners; PUT conf vendored in git.
- `ccproxy/pipeline:local` (6.72 GB): one image, `mtg render|pdf|upscale|version`;
  Chromium 156.0.8078.108 (bookworm apt, **unpinned by decision**), CUDA-capable
  torch 2.15.0+cu132, ccAutomator/MtgPng2Pdf/Ilaria-engines @ pinned SHAs,
  Real-ESRGAN weights baked from `pipeline/models/` (populated by
  `fetch-weights.sh`).
- filebrowser: **pull-only**, digest-pinned in compose (no build).
- Deployed on `.216` at `/conf/ccProxy`: new cardconjurer on host ports
  **5241–5244** (overridable via CC_PORT_1..4), filebrowser :8080; shared
  data dir `.216:/conf/ccProxy/data` (scryfall + centered-text caches at its
  TOP level; env var the code reads is `CC_AUTOMATOR_DATA_DIR`).
- Old stack still up: driver on the local box (`/data/ccAutomator`,
  `.venv/bin/python`, Chromium 135), old 5×nginx on `.216` 4241–4244,
  uploads landing `.216:/data` (nginx → `/usr/share/nginx/html/local_art`).
  `mtgproxy`/`mtgprint` = 172.17.1.216 in the local /etc/hosts.

User rulings (date — do not revisit unilaterally):
- 2026-11-23 **Keep Chromium 156** in the image (not pin the old 135):
  A/B showed the only old↔new output gap is an art-region decode delta
  (max 29/255, no color shift, layout pixel-identical) attributable solely
  to the Chromium version. Recorded + accepted in `bringup.md`.
- 2026-11-24 **Upscale must use the GPU when available** (all current hosts
  are CPU-only, incl. .217's old Ilaria). Image therefore ships the
  default CUDA-capable torch (NOT the CPU wheel index); engines.py
  auto-picks the device. Don't re-pin CPU torch.
- 2026-11-24 Production PDF layout is the **`--cameo`** mode, letter
  portrait **2×3 (6-slot)** ("cameo matless" — user's term; no such flag
  in code). The plain grid + `--cut-lines` mode is the other one.
- 2026-11-24 **Build/publish: GitHub Actions → Docker Hub, PUBLIC**
  (`matthewddunlap/ccproxy-{cardconjurer,pipeline}`, `:latest` + `<sha7>`).
  Rejected the same day, in order: GHCR (free tier = 1 GB storage vs our
  11.3 GB), a LAN registry + self-hosted runner on .216 (user: builds do
  not happen on .216), and trimming cardconjurer's frame set down to just
  Seventh/seventhTextless (keep the FULL frame set — do not corner the
  frame choice). Docker Hub free fits: the cap is **10 GB per LAYER**
  (our biggest layer is 5.71 GB, the torch install), public storage
  fair-use; the repo is public → 2,000 Actions min/mo.

## Traps that already bit (don't relearn the hard way)

1. ccAutomator reads env **`CC_AUTOMATOR_DATA_DIR`** (underscore after CC).
   A misspelling silently falls back to the live Scryfall API + live
   tagger → different card resolution. (Was fixed, c29e646.)
2. `--output-dir` (local-save) mode passes the *local filesystem path* of
   art to the remote app → art window renders **transparent**. Any A/B or
   render against a remote app must use upload mode (`--upload-path` +
   `--image-server`).
3. Cards rendered **before** a `custom.conf` change are invalid A/B
   baselines (custom.conf lives in ccAutomator and moves; e.g. `--center-text`
   landed 2026-11-23). Re-render the old stack with the current conf.
4. Dockerfile `ARG`s don't cross `FROM` — re-declare in the stage.
5. filebrowser FATALs without `FILEBROWSER_CONFIG` present in its state
   dir; seed file is `config/filebrowser.yaml` (state files live directly
   in the mounted dir, NOT a nested `data/` subdirectory).
6. Host data dir must be writable by uid 101 (nginx worker) for PUTs.
7. `docker compose run` allocates a TTY → local ssh sessions hang until the
   run finishes (harmless; the work is in the daemon). Detach real builds
   with `setsid ... & ` + log file.
8. `mtg upscale` tile must be 128/192/256/384 (the pinned engine divides by
   it); defaults match the old service (192, scale 4).
