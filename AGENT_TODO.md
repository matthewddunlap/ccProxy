# AGENT TODO — ccProxy

Read `AGENT_OVERVIEW.md` first (status + user rulings). Items live here,
move to `AGENT_DOING.md` when started, and to `AGENT_DONE.md` when finished
(with outcome + verification).

## 1) Flip the production flow to the new stack  [blocked on user]

Old compose stays up until this (bringup.md checklist). Mechanism: change
`--url` (and `--image-server`) in the working conf to the new stack's app
URL. Do this only when the user says go; keep the old stack runnable as
the rollback. Note: .216's compose `image:` refs already point at the
Docker Hub images (pulled + verified 2026-11-24, see AGENT_DONE), so the
flip is conf + service restart only — no rebuild.

## 2) Carried-over follow-ups (from bringup.md "Known deltas", in priority order as written there)

- **X-Upload-Secret**: conf doesn't enforce it (same as today, trusted LAN)
  — hardening is a deliberate follow-up.
- **`--upscale-art` in-process wiring** in ccAutomator (engines +
  `mtg upscale` are ready; gradio_client kept for the old remote path).
- **`--decks` / `--workers`** orchestrator mode (native run_batches) in
  ccAutomator; until then `mtg render` takes one decklist.
- **run-all** (`render && pdf` one command) once the handoff contract is
  pinned.
- **Quadlet units** for the quadlet host (same images, same data dir).
