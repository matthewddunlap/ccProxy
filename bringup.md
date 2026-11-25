# ccProxy bring-up & verification

## Build (any host with a docker/podman builder — .216 today)

```sh
git clone git@github.com:matthewddunlap/ccProxy.git
cd ccProxy
./pipeline/fetch-weights.sh          # weights from the pinned Real-ESRGAN releases
docker compose build
```

## First run (fresh machine — zero setup steps)

```sh
git clone https://github.com/matthewddunlap/ccProxy.git && cd ccProxy
docker compose up -d        # the one-shot `init` service seeds the filebrowser
                            # config, creates the data dirs, and makes the data
                            # dir writable (nginx uid 101) — idempotent
printf 'Forest\nBrainstorm\nBrainstorm\n' > data/decks/single.txt
docker compose run --rm pipeline render decks/single.txt    # production conf + URL baked in
docker compose run --rm pipeline pdf    decks/single.txt    # production cameo layout
```

(History: these host-side steps used to be manual — `mkdir`/`cp` of the
filebrowser seed config / `chown 101:101 data`; filebrowser FATALs without
its config file. All of that now lives in the `init` compose service.
SELinux hosts: if the mounts come back EACCES, the data/filebrowser
mounts need the shared label (`:z`) or the domain needs `:z` on the mounts.)

## Smoke (optional verification)

```sh
# all four ports serve the app (index.html has no <title>; match the meta keywords)
for p in 4241 4242 4243 4244; do printf "port %s: " "$p"; curl -fsS "http://localhost:$p/" | grep -o 'card, creator, custom, maker'; done

# PUT + HEAD round trip (what the workers do)
curl -fsS -X PUT --data-binary 'hello' http://localhost:4242/local_art/smoke.txt
curl -fsSI  http://localhost:4242/local_art/smoke.txt | head -1
curl -fsS -X DELETE http://localhost:4242/local_art/smoke.txt

# image identity (pins + chromium)
docker compose run --rm pipeline version

# upscale sanity (192 tile, CPU ok)
docker compose run --rm --entrypoint python pipeline -c "from PIL import Image; Image.new('RGB',(192,192),(180,60,30)).save('/data/tile192.png')"
docker compose run --rm pipeline upscale /data/tile192.png /data/out/tile192_x4.png --mode fast --model realesrgan-x2
```

Notes: the PRODUCTION pdf layout is the cameo one (`--cameo`, letter
portrait, 2×3 — "cameo matless"); verified working 2026-11-24 with
registration marks. The plain grid + `--cut-lines` mode (3×3 letter etc.) is
the OTHER mode — `mtg pdf-plain`, fine to use, just not the production
layout.

## A/B against the live stack (byte-identity methodology from the AGENT notes)

1. Same deck + same conf through the OLD stack (`.216` 5×nginx + mtgproxy driver).
2. Same deck + same conf through ccProxy (`mtg render …`).
3. Compare every output PNG byte-for-byte (`sha256sum` both sets).
4. `mtg version` output goes into the test record — it names every pinned SHA
   and the exact chromium that rendered, so any future drift is attributable.

If PNGs differ, first suspect **chromium version** (glyph metrics drive the
auto-fit calibrations): pin the old chromium build into the image, or re-run
the `*_calibrate.py` scripts against the new one and re-compare.

## A/B result — 2026-11-23 (deck: 1 Forest, 2 Brainstorm → Forest lea/294, Brainstorm ice/61)

**Verdict: functionally identical; not byte-identical. The delta is
documented and accepted (decision: keep Chromium 156).**

Test record (`mtg version` from the new image):
```json
{"image":"ccproxy-pipeline","ccautomator":"75677f6ce06ac27bbdc5da1ec6f192c6d4e91be0",
 "mtgpng2pdf":"4bf9b723f3adc294e86b8e3e1cc5e62c39736aa1",
 "ilaria_engines":"57e887c8e2ef20e99b5d20b8d224851c2d8c4700","chromium":"156.0.8078.108"}
```
Old stack: same code@same SHA + same conf + Chromium **135.0.7049.95** (Debian bookworm).

| | new stack (sha256) | old stack (sha256) | pixel diff |
|---|---|---|---|
| Forest lea/294 | `18d2cdfe…cfc0d3` | `f1ebaad5…b8b8c` | **1,878 / 5,656,140 px (0.03%), max Δ1** |
| Brainstorm ice/61 | `635fcbdf…5fa32a` | `f8022aea…c6dfa` | 1,852,180 px (32.7%), **max Δ29**, no channel-mean shift |

- Both stacks are **byte-reproducible run-to-run** (each hash repeated across
  separate runs; old-stack Forest also identical to the 2026-11-18 production
  file). The old↔new gap is therefore deterministic, not timing noise.
- The gap is confined to the **photographic art region** (plus title text
  anti-aliased over the art): per-channel means are identical, no linear gain —
  a decode-level difference (Chromium 135 vs 156 rendering the same JPEG).
  Text over the white rules box is pixel-identical: **all auto-fit
  calibrations transfer cleanly** to Chromium 156.
- Art JPEGs fetched by both runs are byte-identical (`cc62f731…` /
  `e419577f…`), scryfall cache and centered-text cache byte-identical, all app
  assets byte-identical — the renderer was the only uncontrolled variable.

**A/B traps hit this round (documented so they don't bite again):**
1. ccAutomator reads `CC_AUTOMATOR_DATA_DIR` — a misspelled env silently makes
   the container fall back to the live Scryfall API (different print
   resolution) and live tagger fetch. (Fixed in compose/mtg.)
2. `--output-dir` (local-save mode) hands the *local filesystem path* of the
   art to the remote app, which cannot load it → the art window renders
   transparent. A/B must use the production upload path (`--upload-path` +
   `--image-server`).
3. Production cards rendered **before** a `custom.conf` change are not a valid
   baseline (e.g. Brainstorm 2026-11-18 predates `--center-text`, committed
   2026-11-23). Re-render the old stack with the current conf.

## 5→1 nginx collapse: test plan (results 2026-11-23)

All five old containers served byte-identical content from the same mounts, so
one container with four listeners is *supposed* to be a no-op. Proving it:

- [x] static equivalence: all app assets (index, main-1.js, htmx.min.js,
      themes.js, css) **sha256-identical** old 4242 vs new 5242
- [x] PUT + HEAD + GET + DELETE round trip on each of the 4 ports
      (201/200/204); file visible in filebrowser (`/raw/…` 200)
- [x] concurrency: two `render` runs truly in parallel — both green, correct
      card each, no cross-contamination
- [x] A/B above — see result; delta documented & accepted
- [ ] old five-container compose stays up until flip; flipping is a `--url` in
      the conf (old stack verified still serving on 4241–4244)

## Known deltas / follow-ups (deliberate, tracked)

- **Chromium is not version-pinned in the image (deliberate, 2026-11-23)**:
  the A/B showed only an art-region decode delta (max 29/255, no color shift)
  vs the old stack's Chromium 135; decision was to keep the modern Chromium
  rather than pin the EOL 135 build. Consequence: a rebuild after a bookworm
  chromium update may shift art-region pixels again — `mtg version` records
  the exact chromium in every test record, so any drift stays attributable.
  Layout/text calibrations already verified to transfer (see A/B result).
- **X-Upload-Secret**: the client sends it; the (vendored) conf does not
  enforce it — same as today, on a trusted LAN. Hardening is a follow-up.
- **gradio_client** is still installed so the pinned ccAutomator's remote
  upscale path works unchanged; the in-process `--upscale-art` wiring is a
  follow-up code change in ccAutomator (engines + `mtg upscale` are ready).
- **`--decks` / `--workers`** (orchestrator mode, the native run_batches) is a
  follow-up change in ccAutomator; until then `render` takes one decklist and
  you loop externally.
- **run-all** (`mtg render … && mtg pdf …` as one command) once the
  render→pdf handoff contract is pinned down.
- **Quadlet units**: translate this compose.yaml (image + port + volume + env)
  into `.container` units for the quadlet host; same images, same data dir.

## End-to-end test — `cctest` (published image)  [2026-11-25]

A clean end-to-end run of the **published** Docker Hub image on the test
deployment `cctest` (`.216:/tmp/ccfresh`, app **5341–4**, filebrowser **8081**,
data **`/tmp/ccfresh/data`**), offline/deterministic.

**Result: GREEN.** render A/B deck (Forest ×1, Brainstorm ×2) → 2 card PNGs,
offline (809/33 local-cache prints; NOT live API), exit 0; card sha256
**byte-identical** to the A/B baseline + the main local `:local` build
(forest `18d2cdfe…cfc0d3`, brainstorm `635fcbdf…5fa32a`). pdf (cameo, letter
portrait 2×3) → `out/e2e.pdf`, **1 page**, 505,930 B (main verified
`smoke_cameo.pdf`, same deck = 507,745 B). `mtg version`: ccautomator 75677f6,
mtgpng2pdf 4bf9b723, ilaria 57e887c, chromium 156.0.8078.108.

**Issues the e2e caught (fresh-deploy regressions):**
1. **`init` service ownership bug (REAL) — FIXED in `compose.yaml`.** `init`
   creates `card_images/teaching` as **root:755** (only `chmod 777 /data`
   top). The cardconjurer nginx worker is **uid 101** → PUT of a rendered
   card → `[crit] open() …/card_images/teaching/<card>.png.00000000NN failed
   (13: Permission denied)` → **HTTP 500**. (App-created `art/original` =
   101:101 → works.) Fix: `init` now also runs
   `chown -R 101:101 /data/decks /data/out /data/card_images`. Verified on a
   fresh deploy (cce2e): cards PUT with no manual chown.
2. **Deck format (test gotcha, no code fix).** MtgPng2Pdf "Deck List Mode"
   SKIPS any deck line that does NOT start with a digit → bare `Forest` lines
   drop out → "No images to print". ccAutomator render is lenient (bare names
   OK). Use **Moxfield** (`1 Forest` / `2 Brainstorm`) for both steps.
3. **`decks/prime.txt` missing on a fresh deploy (REAL) — FIXED in
   `compose.yaml`.** The baked production `custom.conf` runs ccAutomator with
   `--prime-file decks/prime.txt`, and ccAutomator `exit(1)`s if it is
   missing ("Error: Input file not found at 'decks/prime.txt'"). The old
   stack had it in the driver CWD; both .216 data dirs had been
   host-side-copied (same 45 B file) — which is why cctest looked green.
   Fix: vendored at `config/prime.txt`; `init` seeds it into the data dir
   **only if absent** (a user's own copy wins). Verified on cce2e: `init`
   created it before render.

**Determinism findings (2026-11-25, repeatable-script work):**
- Fully offline render needs **both** caches in the data dir:
  `scryfall_cache.db` (card resolution) and `centered_text_cache.json`
  (centered-text taggings). Without the second, ccAutomator fetches the
  Scryfall Tagger live (a fresh fetch produced a different cache,
  `9c7b7c2f…` vs cctest's `67910056…`).
- **PNG identity is per-context.** On a FRESH stack (app + data) render is
  byte-identical to the A/B baseline — reproduced on cce2e, incl. the
  505,930 B cameo PDF. But on a stack whose app carries residue from a prior
  failed/interrupted session, the SAME pixels came out with a different
  deflate stream (brainstorm `5edd7d01…` vs `635fcbdf…`; pixels verified
  identical — the PNG is encoded in-browser via
  `cardCanvas.toDataURL('image/png')`). `scripts/e2e.sh` asserts byte
  identity AND, on mismatch, diagnoses against a pixel digest (sha256 of
  decoded RGBA) so a context/encoding difference is not mistaken for a
  render regression.
- For byte-identical re-runs: start FRESH (stop the app, clear `data/art` +
  `data/card_images`) and seed both caches.

**Repeatable: `scripts/e2e.sh`** (replaces the manual recipe). From a
checkout, on a docker host:
```sh
E2E_PROJECT=cce2e CC_PORT_1=5351 CC_PORT_2=5352 CC_PORT_3=5353 CC_PORT_4=5354 \
FILEBROWSER_PORT=8082 E2E_CACHE_SRC=/conf/ccProxy/data sh scripts/e2e.sh
```
It brings the project up (init seeds filebrowser config + prime.txt + chowns),
checks `mtg version` pins, seeds the Moxfield fixture deck + caches, renders
(asserts offline resolution + no live fetches + **byte-identical cards**,
with pixel-digest diagnosis on mismatch), and produces the cameo PDF (1 page,
valid header). `E2E_DOWN=1` tears the project down. Render is ~2–3 min
Selenium — over ssh, run detached + poll (a 120s foreground ssh kills it).

**Verification (fresh deploy `cce2e`, `.216:/tmp/cce2e`, published image,
2026-11-25):** full script from a fresh app + data dir, NO manual chown /
prime.txt seeding — GREEN end-to-end: version pins OK; render offline (809
local-cache prints, no live fetches); cards `18d2cdfe…cfc0d3` /
`635fcbdf…5fa32a` (byte-identical to cctest + A/B baseline); cameo PDF
505,930 B, 1 page. Two fresh-stack runs green.
