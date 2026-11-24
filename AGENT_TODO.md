# AGENT TODO — ccProxy

Read `AGENT_OVERVIEW.md` first (status + user rulings). Items live here,
move to `AGENT_DOING.md` when started, and to `AGENT_DONE.md` when finished
(with outcome + verification).

## 1) GitHub Actions: build + push images to a container registry  [NEXT — to discuss with user]

The upcoming topic. Design constraints discovered during bring-up that shape
it — bring these to the discussion, don't rediscover them:

- **Two built images, one pull-only:** `cardconjurer` (4.62 GB) and
  `pipeline` (6.72 GB) are built; filebrowser is a digest-pinned pull —
  the workflow only needs to build/push the two, but compose must keep
  working both from the registry AND locally (`image:` + `build:` pattern;
  decide the tag scheme — today everything is `:local`).
- **pipeline build inputs:** pinned source SHAs fetched at build time from
  codeload (fine in CI), **Real-ESRGAN weights** from `pipeline/models/`
  (populated by `./pipeline/fetch-weights.sh` — 67 MB, SHA256SUMS recorded;
  in CI either run the fetcher in a pre-step or fetch in the Dockerfile —
  decide), and **~4.7 GB of CUDA-capable torch wheels** downloaded by pip
  (user ruling: keep the CUDA build, NOT the CPU wheel index).
- **Image sizes are large** (4.6 + 6.7 GB) → registry push time/storage
  matters; hosts are all amd64 (single-arch is fine for v1).
- **Chromium is unpinned by decision** (bookworm apt, 156.0.8078.108 as of
  build date). CI rebuilds after a bookworm update WILL shift
  art-region pixels (max ~29/255, no color shift — the accepted class of
  drift). `mtg version` bakes the exact chromium + all SHAs into the image,
  so tag/pin accordingly (e.g. build-date or digest-tagging) to keep every
  pushed image attributable.
- **Reproducibility record already exists:** `mtg version` prints
  ccAutomator/MtgPng2Pdf/Ilaria SHAs + chromium version — keep that
  contract if the Dockerfile changes.
- Where to store: user to pick registry (GHCR is the natural default for
  GitHub Actions; other options exist). Secrets/tokens, retention, and
  who may pull are user decisions.
- After switching compose `image:` refs to registry tags, re-verify on
  .216: pull + `mtg version` + the bringup.md smoke set (render must
  resolve cards from the shared cache — check `CC_AUTOMATOR_DATA_DIR`).

## 2) Flip the production flow to the new stack  [blocked on user]

Old compose stays up until this (bringup.md checklist). Mechanism: change
`--url` (and `--image-server`) in the working conf to the new stack's app
URL. Do this only when the user says go; keep the old stack runnable as
the rollback.

## 3) Carried-over follow-ups (from bringup.md "Known deltas", in priority order as written there)

- **X-Upload-Secret**: conf doesn't enforce it (same as today, trusted LAN)
  — hardening is a deliberate follow-up.
- **`--upscale-art` in-process wiring** in ccAutomator (engines +
  `mtg upscale` are ready; gradio_client kept for the old remote path).
- **`--decks` / `--workers`** orchestrator mode (native run_batches) in
  ccAutomator; until then `mtg render` takes one decklist.
- **run-all** (`render && pdf` one command) once the handoff contract is
  pinned.
- **Quadlet units** for the quadlet host (same images, same data dir).
