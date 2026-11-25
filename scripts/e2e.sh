#!/bin/sh
# ccProxy end-to-end test — renders a deck and produces the production cameo
# PDF against a compose project of THIS repo, on a docker host, then asserts
# the known-good results. This is the repeatable form of the 2026-11-25
# `cctest` green run (recorded in bringup.md).
#
# Usage (from a checkout of this repo, on a host with docker + compose v2):
#
#   E2E_CACHE_SRC=/path/to/scryfall_cache.db sh scripts/e2e.sh
#
# Environment (all optional):
#   E2E_PROJECT       compose project name (default cctest; keep distinct from
#                     any other running stack's project so ports/networks don't
#                     collide)
#   CC_PORT_1..4      cardconjurer host ports (defaults 4241-4; override when
#                     running beside another stack)
#   FILEBROWSER_PORT  filebrowser host port (default 8080)
#   E2E_CACHE_SRC     a DATA DIR with the caches to seed into ./data — the
#                     live stack's data dir (e.g. /conf/ccProxy/data) works
#                     as-is: it copies scryfall_cache.db (required) +
#                     centered_text_cache.json (if present). Seeding makes
#                     render resolve OFFLINE/deterministically and enables the
#                     byte-identity assertions — the centered-text cache
#                     drives card typesetting, so a live re-fetch can change
#                     the PNGs. Without it (and no cache already in ./data),
#                     render falls back to the live API and the sha256
#                     assertions are skipped.
#   E2E_DOWN          1 = tear the project down at the end (default: leave it
#                     up for inspection)
#
# Steps: up app -> seed Moxfield deck -> render (Selenium, ~2-3 min) -> assert
# cards -> cameo pdf -> assert pdf. Leaves logs in ./data/e2e_*.log.
#
# Deck format gotcha: the PDF step needs Moxfield counts (lines starting with
# a digit) — MtgPng2Pdf deck-list mode silently skips bare names. ccAutomator
# render accepts bare names, so a mixed-format deck looks green on render and
# dies on pdf. This script uses Moxfield for both, on purpose.

set -eu

cd "$(dirname -- "$0")/.."
ROOT="$(pwd -P)"
DATA="$ROOT/data"

PROJECT="${E2E_PROJECT:-cctest}"
CACHE_SRC="${E2E_CACHE_SRC:-}"
DECK_REL="decks/e2e.txt"          # host path under data/; container arg is the same (CWD=/data)
OUT_PDF="$DATA/out/e2e.pdf"
RENDER_LOG="$DATA/e2e_render.log"
PDF_LOG="$DATA/e2e_pdf.log"

# Known-good card digests for the A/B fixture deck (1 Forest lea / 2 Brainstorm
# ice), rendered from the pinned scryfall cache — byte-identical across the
# A/B baseline (2026-11-23), the local :local build, and the published
# :latest image (cctest + fresh cce2e, 2026-11-25).
EXPECT_FOREST="18d2cdfe93c2c20fe0834184c922580bd350fdb1b9b858d5ead9b25aa1cfc0d3"
EXPECT_BRAIN="635fcbdf79ce16da9aaffbda5f0f05f7fc5f4794b6cd7fd630e977262f5fa32a"
FOREST_PNG="$DATA/card_images/teaching/forest_lea_294.png"
BRAIN_PNG="$DATA/card_images/teaching/brainstorm_ice_61.png"

# Known-good PIXEL digests (sha256 of decoded RGBA, encoder-independent; same
# provenance). The card PNG is encoded in-browser (cardCanvas.toDataURL), and
# a stack whose app carries residue from a prior failed/interrupted session
# can emit a different deflate stream for the SAME pixels (observed
# 2026-11-25: brainstorm 5edd7d01… vs 635fcbdf…, pixels identical). A digest
# mismatch is therefore diagnosed against these before failing.
EXPECT_PIXEL_FOREST="ac5f7a91d4b79d96d9deb422633caf6be6df4693a42043728381532d1757d566"
EXPECT_PIXEL_BRAIN="623c9b0ed2104dc49dabc36ab1c0b3a8bee42bfe5c0c2be44650dc0f0230e34d"

# Source pins (pins.txt) — `mtg version` must carry all four.
EXPECT_CC="75677f6"      # ccAutomator
EXPECT_PDF="4bf9b723"    # MtgPng2Pdf
EXPECT_IL="57e887c"      # Ilaria engines
EXPECT_CR="156.0.8078.108"

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

dc() { docker compose -p "$PROJECT" "$@"; }

[ "$(id -u)" = 0 ] || echo "note: not root — data-dir writes need to be permitted for user $(id -un)"

mkdir -p "$DATA/decks" "$DATA/out" "$DATA/card_images/teaching"

# --- 0. seed deterministic fixtures ----------------------------------------
# STRICT = fully offline render asserted (both caches in the data dir).
STRICT=0
if [ -n "$CACHE_SRC" ]; then
  [ -f "$CACHE_SRC/scryfall_cache.db" ] || fail "E2E_CACHE_SRC=$CACHE_SRC has no scryfall_cache.db"
  cp -f "$CACHE_SRC/scryfall_cache.db" "$DATA/scryfall_cache.db"
  [ -f "$CACHE_SRC/centered_text_cache.json" ] && cp -f "$CACHE_SRC/centered_text_cache.json" "$DATA/centered_text_cache.json"
  pass "seeded caches from $CACHE_SRC"
elif [ -f "$DATA/scryfall_cache.db" ]; then
  pass "using existing scryfall cache in data dir"
else
  echo "WARN  no scryfall cache: render will hit the LIVE API (non-deterministic); sha256 assertions skipped"
fi
[ -f "$DATA/scryfall_cache.db" ] && [ -f "$DATA/centered_text_cache.json" ] && STRICT=1
printf '1 Forest\n2 Brainstorm\n' > "$DATA/$DECK_REL"
pass "seeded Moxfield deck: 1 Forest / 2 Brainstorm"

# --- 1. bring the stack up (idempotent; init service seeds config + chowns) -
dc up -d cardconjurer filebrowser
pass "compose project '$PROJECT' up (cardconjurer + filebrowser)"

# --- 2. version identity ----------------------------------------------------
VER="$(dc run --rm -T pipeline version)"
printf '%s\n' "$VER" | sed 's/^/      /'
for pair in "ccautomator:$EXPECT_CC" "mtgpng2pdf:$EXPECT_PDF" "ilaria_engines:$EXPECT_IL" "chromium:$EXPECT_CR"; do
  key="${pair%%:*}"; want="${pair#*:}"
  printf '%s' "$VER" | grep -q "\"$key\":\"$want" || fail "version: $key does not carry pin $want"
  pass "version: $key carries pin $want"
done

# --- 3. render (Selenium; the slow step) ------------------------------------
dc run --rm -T pipeline render "$DECK_REL" > "$RENDER_LOG" 2>&1 \
  || { grep -q "Input file not found at 'decks/prime.txt'" "$RENDER_LOG" \
         && echo "hint: ccAutomator exit(1) on missing prime-file — the init service seeds decks/prime.txt; did it run with the current compose.yaml?" >&2
       printf '%s\n' "$RENDER_LOG" | tail -40 >&2
       fail "render exited non-zero (log: $RENDER_LOG)"; }
grep -q "decklist: all cards resolved." "$RENDER_LOG" || { tail -40 "$RENDER_LOG" >&2; fail "render: no 'decklist: all cards resolved.' in log"; }
pass "render: decklist: all cards resolved."
grep -Eq "Resolved [1-9][0-9]* local cache print" "$RENDER_LOG" \
  || { grep -i "resolved" "$RENDER_LOG" >&2 || true; fail "render: not resolved from local cache (offline mode required for determinism)"; }
pass "render: $(grep -Eo 'Resolved [0-9]+ local cache print' "$RENDER_LOG" | head -1) (offline)"
if [ "$STRICT" = 1 ] && grep -q "fetching 'centered text' tag" "$RENDER_LOG"; then
  fail "render hit the LIVE Scryfall Tagger (centered-text cache miss) — not deterministic"
fi
[ "$STRICT" = 1 ] && pass "render: no live API fetches (fully offline)"
[ -f "$FOREST_PNG" ]   || fail "render: missing $FOREST_PNG"
[ -f "$BRAIN_PNG" ]    || fail "render: missing $BRAIN_PNG"
grep -q "Automation complete." "$RENDER_LOG" || { tail -20 "$RENDER_LOG" >&2; fail "render: no 'Automation complete.' in log"; }
pass "render: both card PNGs present; Automation complete."

if [ -n "$CACHE_SRC" ] || [ -f "$DATA/scryfall_cache.db" ]; then
  # pixel_hash <png> — sha256 of the decoded RGBA pixels (runs in the pipeline
  # image, which has PIL); the script's own dir is NOT mounted into the
  # container, so the helper is staged into the data dir first.
  cp -f scripts/pngphash.py "$DATA/pngphash.py"
  pixel_hash() { dc run --rm --entrypoint python -T pipeline pngphash.py "$1" | awk '{print $1}'; }
  for quad in "$FOREST_PNG:$EXPECT_FOREST:$EXPECT_PIXEL_FOREST" "$BRAIN_PNG:$EXPECT_BRAIN:$EXPECT_PIXEL_BRAIN"; do
    f="${quad%%:*}"; rest="${quad#*:}"; want="${rest%%:*}"; wantpx="${rest#*:}"
    got="$(sha256sum "$f" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
      gotpx="$(pixel_hash "$f")"
      if [ "$gotpx" = "$wantpx" ]; then
        fail "card pixels IDENTICAL to known-good but byte stream differs ($f: $got, want $want) — this stack's app carries residue from a prior session; re-run on a FRESH stack (stop the app, clear data/art + data/card_images) to reproduce byte identity"
      fi
      fail "card digest AND pixels differ from known-good ($f: bytes $got, pixels $gotpx) — a real render difference"
    fi
    pass "card digest byte-identical: $(basename "$f")"
  done
else
  echo "skip  card digest assertions (no cache)"
fi

# --- 4. cameo pdf (production layout) ----------------------------------------
dc run --rm -T pipeline pdf "$DECK_REL" > "$PDF_LOG" 2>&1 \
  || { printf '%s\n' "$PDF_LOG" | tail -40 >&2; fail "pdf exited non-zero (log: $PDF_LOG)"; }
grep -q "Cameo PDF generation successful" "$PDF_LOG" || { tail -40 "$PDF_LOG" >&2; fail "pdf: no success line in log"; }
grep -q "1 page(s)" "$PDF_LOG" || { tail -20 "$PDF_LOG" >&2; fail "pdf: expected 1 page"; }
[ -f "$OUT_PDF" ] || fail "pdf: missing $OUT_PDF"
head -c 5 "$OUT_PDF" | grep -q "%PDF" || fail "pdf: $OUT_PDF does not start with %PDF"
pass "pdf: $OUT_PDF ($(wc -c < "$OUT_PDF") bytes), 1 page, valid %PDF header"

# --- 5. leave up or tear down ------------------------------------------------
if [ "${E2E_DOWN:-0}" = 1 ]; then
  dc down --remove-orphans
  echo "tore down project '$PROJECT'"
else
  echo "left project '$PROJECT' up (app on \${CC_PORT_1:-4241}-…; set E2E_DOWN=1 to tear down)"
fi

echo
echo "E2E GREEN: render -> cards -> cameo pdf, all assertions passed."
