# AGENT DONE — completed items

## Repeatable e2e + fresh-deploy fixes — verified  [2026-11-25]

The e2e-tests item (former TODO #1) — DONE, verified on a FRESH deploy
(`cce2e`, `.216:/tmp/cce2e`, published `matthewddunlap/ccproxy-*:latest`).
Commits: see `git log` after this session (compose fixes + `scripts/e2e.sh`
+ docs). **Push pending user confirmation.**

- **`init` chown fix (REAL bug, app-PUT 500):** `compose.yaml` `init`
  entrypoint now ends with `chown -R 101:101 /data/decks /data/out
  /data/card_images` (was root:755 → nginx uid-101 worker EACCES → HTTP 500
  on card PUT). Verified: fresh cce2e deploy rendered + PUT both cards with
  NO manual chown.
- **`decks/prime.txt` seeding (REAL bug, 3rd fresh-deploy issue):** the
  baked production `custom.conf` runs ccAutomator with `--prime-file
  decks/prime.txt`; ccAutomator `exit(1)`s on a missing file. Both .216
  data dirs had been host-side-copied (why cctest looked green). Vendored
  `config/prime.txt`; `init` seeds it only-if-absent (user's copy wins).
  Verified on cce2e (init created it before render).
- **`scripts/e2e.sh`** (+ `scripts/pngphash.py` helper): up → `mtg version`
  pin checks → seed Moxfield deck + BOTH caches (`E2E_CACHE_SRC` = a data
  dir) → render (asserts offline resolution, NO live Tagger/Scryfall
  fetches, byte-identical cards with a pixel-digest diagnosis on mismatch)
  → cameo PDF (1 page, valid header). `E2E_DOWN=1` tears down.
- **Determinism findings (in bringup.md):** offline render needs BOTH
  caches (scryfall + centered-text; a live Tagger re-fetch made a different
  cache). PNG identity is per-context: FRESH app+data → byte-identical (and
  505,930 B PDF); an app with residue from an interrupted session can emit a
  different deflate stream for the SAME pixels (encoded in-browser,
  `cardCanvas.toDataURL`).
- **Verification:** two full fresh-stack runs GREEN: version pins
  (ccautomator 75677f6 / mtgpng2pdf 4bf9b723 / ilaria 57e887c / chromium
  156.0.8078.108); render 809 local-cache prints, no live fetches; cards
  `18d2cdfe…cfc0d3` / `635fcbdf…5fa32a` (== cctest + A/B baseline); cameo
  PDF 505,930 B, 1 page.

## End-to-end test cycle on `cctest` (published image) — GREEN  [2026-11-25]

Drove the in-flight `cctest` e2e on `.216` (published `matthewddunlap/ccproxy-*:latest`)
from STUCK (no cards/PDF) to a full green render→pdf, offline/deterministic. Verified:
- **render** A/B deck (Forest ×1, Brainstorm ×2) → `forest_lea_294.png` +
  `brainstorm_ice_61.png`, **offline** (809/33 local-cache prints; NOT live API), exit 0.
  Card sha256 **byte-identical** to the A/B baseline + the main local `:local` build:
  `18d2cdfe…cfc0d3` (forest) / `635fcbdf…5fa32a` (brainstorm).
- **pdf** (cameo, letter portrait 2×3) → `out/e2e.pdf`, **1 page**, 505,930 B, valid
  %PDF-1.4 (main verified `smoke_cameo.pdf`, same deck = 507,745 B).
- **2 issues found + worked around** (the e2e caught both on a fresh deploy):
  1. `init` service leaves `card_images/` root-owned (755) → cardconjurer nginx worker
     (**uid 101**) can't PUT a rendered card → **HTTP 500** ("Permission denied"). Fixed
     ad-hoc on `.216` (`chown -R 101:101 /tmp/ccfresh/data/card_images`); **repo `init`
     fix still TODO** (TODO #1a).
  2. MtgPng2Pdf "Deck List Mode" SKIPS bare-name deck lines (needs Moxfield `1 Forest`);
     ccAutomator render is lenient. Use Moxfield for both steps.
- Venue/commands + exact recipe + next steps: `AGENT_DOING.md` + `bringup.md`.

## GitHub Actions → Docker Hub publication  [2026-11-24]

The "build + store the images" topic (former TODO #1) — **live and verified**.
Ruling + rationale: AGENT_OVERVIEW (2026-11-24 build/publish entry).

- **Workflow** `.github/workflows/build-images.yml` — `ca10995` (first),
  `fc955c2` (YAML typo: unquoted `:` in step names), `e9de012` (final:
  `paths` gate so doc-only pushes don't rebuild an 11 GB image). Two jobs
  = two runners (the pipeline build peaks near a runner's disk budget:
  ~4.7 GB torch wheels); `workflow_dispatch` = deliberate re-bake (e.g.
  after bookworm bumps Chromium).
- **Published (public, per ruling):** `docker.io/matthewddunlap/ccproxy-pipeline`
  + `matthewddunlap/ccproxy-cardconjurer`, tags `latest` + `e9de012`
  (head SHA — attributable; `mtg version` inside also bakes all source
  SHAs + chromium).
- **First green run:** [actions/runs/45476499707](https://github.com/matthewddunlap/ccProxy/actions/runs/45476499707)
  (run #1 failed on the YAML typo; #2 was superseded by #3 via the
  concurrency group — both expected).
- **CI sanity:** weights fetch (self-verifying), `mtg version` (all pins +
  Chromium 156.0.8078.108), upscale smoke (192 tile, CPU), cardconjurer
  HTTP check. Render/PDF smokes stay on the deploying host — they need
  the bringup assets in `data/`, which are gitignored by design.
- **Delivery verified 2026-11-24:** pulled `latest` from Docker Hub on
  **.216 (both images)** and **.217 (pipeline)** — standard HTTPS, no
  daemon config; `mtg version` on the pulled images shows every source
  SHA + chromium intact.
- **Rejected this session (do not re-litigate without the user):** GHCR
  (free tier = 1 GB storage vs our 11.3 GB), LAN registry + self-hosted
  runner on .216 (user: no builds on .216), cardconjurer frame trimming
  to just Seventh/seventhTextless (keep the FULL frame set — don't corner
  the frame choice; the exact keep-list was mapped out and shelved).
  The abandoned LAN-registry leftovers on .216 were cleaned (registry:2
  image, orphaned `ccproxy/*:latest` tags, `build.sh`).

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
