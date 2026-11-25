# AGENT TODO — ccProxy

Read `AGENT_OVERVIEW.md` first (status + user rulings). Items live here,
move to `AGENT_DOING.md` when started, and to `AGENT_DONE.md` when finished
(with outcome + verification).

## 1) End-to-end tests (make it repeatable)  [ACTIVE — full detail in AGENT_DOING.md]

`cctest` e2e on `.216` (published `matthewddunlap/ccproxy-*:latest`) is GREEN
end-to-end: render→pdf, offline/deterministic, cards byte-identical to the A/B
baseline (see AGENT_DONE, 2026-11-25). Left in flight:
- **(a) repo fix** — `init` service leaves `card_images/` root-owned → cardconjurer
  nginx worker (uid 101) can't PUT a rendered card → **HTTP 500**. Append to the `init`
  entrypoint in `compose.yaml`: `chown -R 101:101 /data/decks /data/out /data/card_images`.
- **(b) repeatable script** — add `scripts/e2e.sh` (seed offline cache → render [assert
  "Resolved N local cache" + card sha256 == known-good] → cameo pdf [assert 1 page + valid],
  print `mtg version` identity; PASS/FAIL).
- **(c) bringup.md** section for the cctest e2e result + the 2 gotchas (see (a) + the
  Moxfield-deck-format gotcha: PDF step needs `1 Forest`, render is lenient).
- **(d) commit + push** — commit locally (trailer `Co-Authored-By: Claude Code <noreply@anthropic.com>`);
  **confirm with the user before pushing** (outward).

## 2) Flip the production flow to the new stack  [blocked on user]

Old compose stays up until this (bringup.md checklist). Mechanism: change
`--url` (and `--image-server`) in the working conf to the new stack's app
URL. Do this only when the user says go; keep the old stack runnable as
the rollback. Note: .216's compose `image:` refs already point at the
Docker Hub images (pulled + verified 2026-11-24, see AGENT_DONE), so the
flip is conf + service restart only — no rebuild.

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
