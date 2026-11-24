# AGENT TODO — ccProxy

Read `AGENT_OVERVIEW.md` first (status + user rulings). Items live here,
move to `AGENT_DOING.md` when started, and to `AGENT_DONE.md` when finished
(with outcome + verification).

## 1) GitHub Actions → Docker Hub publication  [IN FLIGHT — see AGENT_DOING]

Decided + implemented 2026-11-24 (ruling recorded in AGENT_OVERVIEW):
Actions builds both images on GitHub-hosted runners, sanity-checks
(`mtg version`, upscale smoke, cardconjurer serves), pushes PUBLIC
`matthewddunlap/ccproxy-{cardconjurer,pipeline}` as `:latest` + `<sha7>`.
Workflow: `.github/workflows/build-images.yml` — two jobs = two runners
(the pipeline build peaks near a runner's disk budget: ~4.7 GB torch
wheels + 5.71 GB layer); weights fetched in-job via the existing
self-verifying `pipeline/fetch-weights.sh`; Chromium still unpinned by
ruling, so `<sha7>` + the baked `mtg version` JSON keep every push
attributable. Run #1 failed on a YAML typo (unquoted colon in a step
name), fixed in `fc955c2`; run #2 in flight.

Remaining after the first green run:
- Pull + `mtg version` from a second host (.216 and/or .217) to prove
  delivery — no daemon config needed, Docker Hub is standard HTTPS.
- The full render/PDF smokes run on the deploying host (they need the
  bringup assets in `data/`, which is gitignored — CI cannot run them).
  Render must resolve from the shared cache — check `CC_AUTOMATOR_DATA_DIR`.
- When the user flips (item 2), .216's compose already references the
  Docker Hub names (`image:` + kept `build:`).

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
