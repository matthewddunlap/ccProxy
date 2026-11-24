# ccProxy bring-up & verification

## Build (any host with a docker/podman builder — .216 today)

```sh
git clone git@github.com:matthewddunlap/ccProxy.git
cd ccProxy
./pipeline/fetch-weights.sh          # weights from the pinned Real-ESRGAN releases
docker compose build
```

## First run

```sh
mkdir -p data/decks data/out data/cache
chown -R 101:101 data    # nginx worker (uid 101) must be able to write PUT targets
mkdir -p filebrowser && cp config/filebrowser.yaml filebrowser/config.yaml
docker compose up -d cardconjurer filebrowser
# (filebrowser FATALs without its config file — the seed above is the one from
#  the live .216 deployment, adapted to this stack's /data mount)

# smoke: all four ports serve the app (index.html has no <title>; match the meta keywords)
for p in 4241 4242 4243 4244; do printf "port %s: " "$p"; curl -fsS "http://localhost:$p/" | grep -o 'card, creator, custom, maker'; done

# smoke: PUT + HEAD round trip (what the workers do)
curl -fsS -X PUT --data-binary 'hello' http://localhost:4242/local_art/smoke.txt
curl -fsSI  http://localhost:4242/local_art/smoke.txt | head -1
curl -fsS -X DELETE http://localhost:4242/local_art/smoke.txt

# render one small deck (same flags as today's custom.conf)
docker compose run --rm pipeline version
docker compose run --rm pipeline render data/decks/single.txt @data/conf/custom.conf

# pdf: the PRODUCTION layout is the cameo one — `--cameo`, letter portrait,
# a 2x3 (6-slot) fixed layout ("cameo matless"); verified working 2026-11-24
# with registration marks. The plain grid + --cut-lines mode (3x3 letter etc.)
# is the OTHER mode — fine to use, just not the production layout.
docker compose run --rm pipeline pdf --cameo --paper-type letter \
    --cameo-orientation portrait --png-dir /data/card_images/teaching \
    --deck-list decks/smoke.txt --output-file /data/out/smoke
```

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
