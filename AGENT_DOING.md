# AGENT DOING — current work item

## NEXT SESSION, START HERE (2026-11-25)

**Active item: END-TO-END TESTS** (user: "resume work on end to end tests").
The in-flight `cctest` e2e on `.216` was STUCK (no cards, no PDF). This session
drove it to a full **GREEN render→pdf on the published image** (offline/
deterministic, cards byte-identical to the A/B baseline) and found **2 real
issues** the e2e caught on a fresh deploy. The green cycle is proven; the
**in-flight deliverable** is to make it REPEATABLE (a committed script) + fix
the one root-cause bug in the repo.

### State at a glance (2026-11-25)
- **e2e GREEN** on `cctest` (`.216`, published `matthewddunlap/ccproxy-*:latest`):
  - render A/B deck (Forest ×1, Brainstorm ×2) → `forest_lea_294.png` +
    `brainstorm_ice_61.png`, **offline** (809/33 local-cache prints; NOT live API), exit 0.
  - card sha256 **byte-identical** to the A/B baseline + the main local `:local` build:
    forest `18d2cdfe…cfc0d3`, brainstorm `635fcbdf…5fa32a`.
  - cameo PDF (letter portrait 2×3) → `out/e2e.pdf`, **1 page**, 505,930 B, valid
    %PDF-1.4 (main verified `smoke_cameo.pdf`, same deck = 507,745 B).
  - `mtg version`: ccautomator 75677f6, mtgpng2pdf 4bf9b723, ilaria 57e887c, chromium 156.0.8078.108.
- **Venue = `.216`** = `ssh root@172.17.1.216` (key auth; `BatchMode` non-interactive works).
  **This box has NO docker** — everything runs on `.216`.
- **`cctest`** = `.216:/tmp/ccfresh` (fresh clone of the repo; app **5341–4**, filebrowser
  **8081**; data **`/tmp/ccfresh/data`**). **Main** = `.216:/conf/ccProxy` (local `:local`
  images; app 5241–4; data `/conf/ccProxy/data`). Old 5-container stack still up (4241–4).

### 2 issues the e2e caught (fix status)
1. **`init` service leaves `card_images/` root-owned → app PUT 500** — **REAL BUG, repo fix TODO.**
   - compose `init` runs `mkdir -p …/card_images/teaching` as **ROOT** + only `chmod 777 /data`.
     → `card_images/teaching` = root:755; cardconjurer nginx worker is **uid 101** → PUT of a
     rendered card → `[crit] open() …/card_images/teaching/<card>.png.00000000NN failed (13:
     Permission denied)` → **HTTP 500**. (App-created `art/original` = 101:101 → works.)
   - **Fix (TODO, repo `compose.yaml` `init` entrypoint):** chown the app-writable subdirs to 101 —
     append `chown -R 101:101 /data/decks /data/out /data/card_images`.
   - **Applied ad-hoc on `.216`/cctest to unblock:** `chown -R 101:101 /tmp/ccfresh/data/card_images`.
2. **Deck format: PDF needs Moxfield counts; render is lenient** — **test gotcha (no code fix).**
   - MtgPng2Pdf "Deck List Mode" (`card_processing.py:140`) SKIPS any deck line not STARTING WITH A
     DIGIT → bare `Forest` lines drop → "No images to print". ccAutomator render ACCEPTS bare names.
   - **Use Moxfield** (`1 Forest` / `2 Brainstorm`) for BOTH steps. (Main's working decks are Moxfield.)

### Exact recipe (verified GREEN on `.216`/cctest)
```sh
ssh root@172.17.1.216
# offline/deterministic fixture (render must resolve from cache, not the live API)
cp -f /conf/ccProxy/data/scryfall_cache.db /tmp/ccfresh/data/           # sha256 3feaee8b…
printf '1 Forest\n2 Brainstorm\n' > /tmp/ccfresh/data/decks/e2e.txt     # Moxfield, NOT bare names
chown -R 101:101 /tmp/ccfresh/data/card_images                          # unblock app PUT (issue #1)
# RENDER (Selenium ~2-3 min) — run DETACHED + poll; the 120s Bash/ssh timeout kills a foreground render
cd /tmp/ccfresh
nohup docker compose -p cctest run -T pipeline render decks/e2e.txt > /tmp/ccfresh/e2e_render.log 2>&1 &
#   poll: docker ps | grep cctest-pipeline ; ls /tmp/ccfresh/data/card_images/teaching
#   green: "decklist: all cards resolved." + "Resolved N local cache print(s)" + 2 PNGs + "Automation complete."
# PDF (fast, pure local Python)
docker compose -p cctest run --rm -T pipeline pdf decks/e2e.txt > /tmp/ccfresh/e2e_pdf.log 2>&1
#   green: "Cameo PDF generation successful: /data/out/e2e.pdf (1 page(s))" + out/e2e.pdf ~506KB
```

### Gotchas (so the next context doesn't relearn them)
- The compose file says `name: ccproxy` but the test project runs as **`cctest`** via `-p cctest`
  (that's how it gets its own network + data dir). ALWAYS `docker compose -p cctest …` for the test stack.
- `-T` = no TTY (avoids the ssh TTY-hang trap). With it, stdout is **block-buffered to the log** → no
  live progress; poll the container/card files, read the log after exit.
- Render is the slow part (Selenium). Foreground `docker compose run` over ssh gets killed by the
  120s tool timeout → **always nohup+& + poll** (or a long tool timeout).
- `decks/`, `card_images/`, `out/` live under `data/` on the host (`/tmp/ccfresh/data/…`); inside the
  container the CWD is `/data`, so CLI args are `decks/e2e.txt` etc.
- `mtg pdf` must be given the deck as a POSITIONAL (non-flag) first arg to get the production cameo layout.

### NEXT STEPS (the in-flight deliverable)
1. **Fix the `init` bug** in `/data/ccProxy/compose.yaml` (chown app-writable subdirs to 101). [repo]
2. **Add a repeatable e2e script** to the repo (e.g. `scripts/e2e.sh`): the recipe above + assertions
   (version identity; render "Resolved N local cache" + card sha256 == known-good; PDF 1 page + valid).
3. **bringup.md**: add the cctest e2e result + the 2 gotchas.
4. **Commit** (handoff + fixes; trailer `Co-Authored-By: Claude Code <noreply@anthropic.com>`).
   **Push = confirm with user first** (outward; AGENT/docs push does NOT trigger an image rebuild).
5. (optional) sync the compose fix to `.216` main + a fresh re-clone test.
