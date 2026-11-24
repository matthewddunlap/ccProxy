# AGENT DONE — completed items

## Bring-up + full smoke + A/B  [2026-11-23/24]

Scaffold (prior sessions) → build → smoke → A/B, all verified. Full record +
hashes + methodology: `bringup.md` ("A/B result" + test-plan sections).

- **Images built & deployed** on .216 next to the old stack:
  `ccproxy/cardconjurer:local` 4.62 GB (app @ pinned SHA, 1 container / 4
  listeners), `ccproxy/pipeline:local` (Chromium 156.0.8078.108 + CUDA torch).
- **All four `mtg` commands green:** version (pins + chromium recorded),
  render (2-card deck, full Selenium→PUT), upscale (in-process Real-ESRGAN,
  CPU — engines auto-pick GPU when present), pdf (both modes; production
  cameo letter-portrait 2×3 verified 2026-11-24).
- **5→1 collapse proven:** all app assets sha256-identical old vs new;
  PUT/HEAD/GET/DELETE 201/200/204 on all 4 new ports; two renders run truly
  in parallel, both green, no cross-contamination; filebrowser serves output.
- **A/B verdict:** both stacks byte-reproducible run-to-run; text/layout
  pixel-identical (auto-fit calibrations transfer to Chromium 156); only gap
  = art-region decode delta, max 29/255, no color shift, attributable solely
  to Chromium 135 (old) vs 156 (new). **User ruling: keep 156, documented.**
  Forest: 1,878/5,656,140 px differ, max Δ1. Brainstorm: 32.7% of px, max Δ29,
  per-channel means identical.

## Bugs found & fixed during bring-up (each its own commit)

- **`fc22bc4`** upscale: stop baking in a CPU-only torch build — default
  CUDA-capable torch+torchvision (user ruling: GPU when available); engines
  auto-pick device. Rebuilt on .216 (image 2.03→6.72 GB), upscale smoke
  re-verified on the GPU-less host (torch 2.15.0+cu132, cuda.is_available
  False → CPU path works).
- **`c29e646`** render: env var name — code reads `CC_AUTOMATOR_DATA_DIR`;
  the misspelling made the container silently fall back to live Scryfall
  data (different print resolution + live tagger). compose + `mtg` fixed.
- **`2723187`** upscale: `--tile 0` crashed the pinned engine (divides by
  tile); now mirrors the service contract (default 192; 128/192/256/384
  only; scale 1..4).
- **`9c1d9b0`/`434027f`** bringup/config: filebrowser seed path (state files
  live directly in the mounted dir, not a nested data/).
- **`051e0a1`** compose: filebrowser state mount fixed (mounting the parent
  hid the image's own binary dir) + parity env from the old compose;
  seed config itself committed in **`4d7fcca`**.
- **`566e04f`** Dockerfiles: build ARGs re-declared after FROM (they don't
  cross the stage boundary).
- **`08c00a3`** compose: CC_PORT_1..4 overrides so the stack coexists with
  the old one during A/B; **`6d211c1`** documented the uid-101 data-dir
  ownership requirement.

## Documentation

- `bringup.md`: build/smoke/A/B procedure, A/B result + test record + the
  three A/B traps, 5→1 checklist (all green except the user-gated flip),
  production cameo PDF invocation, chromium decision, carried follow-ups.
- `AGENT_*` handoff set created 2026-11-24 (this file + OVERVIEW/TODO/DOING).
- README: layout + design notes (unchanged, still accurate).
