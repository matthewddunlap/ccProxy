#!/usr/bin/env bash
# ccProxy — build both images locally and publish to the LAN registry.
#
# One command, no magic: the image is exactly what this repo builds
# (pinned source SHAs in the Dockerfiles, ../pins.txt; weights
# self-verified). No trimming, no external CI — LAN in, LAN out.
#
# Usage (on a host with the docker daemon — today: .216):
#   ./build.sh                build + sanity + publish to $REGISTRY
#   REGISTRY= ./build.sh      build + sanity only, skip publish
#   MODELS=all ./build.sh     bake the full Real-ESRGAN lane (default: x2plus only)
#
# Tags: :latest (moving) + <this repo's sha7> (immutable, attributable —
# `mtg version` inside the image prints every source SHA + chromium).
#
# Pulling from another LAN host:
#   docker pull 172.17.1.216:5000/ccproxy/pipeline:latest
# The registry is plain HTTP by design (trusted LAN, like the rest of the
# stack); client daemons need "insecure-registries": ["172.17.1.216:5000"]
# in /etc/docker/daemon.json. The builder itself uses localhost and needs
# no such config.
set -euo pipefail
cd "$(dirname "$0")"

REGISTRY="${REGISTRY:-localhost:5000}"     # set empty to skip publish
NS=ccproxy
IMAGES=(cardconjurer pipeline)
SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"

step() { printf '\n>> %s\n' "$*"; }

step "1/5 weights (self-verifying; skipped if present)"
MODELS="${MODELS:-x2plus}" ./pipeline/fetch-weights.sh

step "2/5 build ${IMAGES[*]} (tags :latest)"
docker compose build "${IMAGES[@]}"

step "3/5 sanity: mtg version (pins + chromium)"
docker run --rm "${NS}/pipeline:latest" version

step "4/5 sanity: upscale (192 tile; CPU ok)"
docker run --rm --entrypoint python "${NS}/pipeline:latest" -c \
  "from PIL import Image; Image.new('RGB',(192,192),(180,60,30)).save('/data/build_smoke_in.png')"
docker run --rm "${NS}/pipeline:latest" \
  upscale /data/build_smoke_in.png /data/build_smoke_out.png --mode fast --model realesrgan-x2

# The cameo-PDF smoke needs the bringup assets (decks/smoke.txt + the
# teaching card PNGs); they live on .216's data dir. Skip gracefully
# elsewhere rather than fail.
if [ -f data/decks/smoke.txt ] && ls data/card_images/teaching/*.png >/dev/null 2>&1; then
  step "5/5 sanity: production cameo PDF (letter portrait 2x3)"
  docker run --rm "${NS}/pipeline:latest" pdf --cameo --paper-type letter \
    --cameo-orientation portrait --png-dir /data/card_images/teaching \
    --deck-list /data/decks/smoke.txt --output-file /data/out/build_smoke
  ls -l data/out/build_smoke*
else
  step "5/5 cameo-PDF smoke skipped (no bringup assets in ./data)"
fi

if [ -n "$REGISTRY" ]; then
  step "publish to $REGISTRY ($NS/*:latest + :$SHA)"
  for n in "${IMAGES[@]}"; do
    docker tag "${NS}/$n:latest" "${NS}/$n:$SHA"
    docker push "$REGISTRY/$NS/$n:latest"
    docker push "$REGISTRY/$NS/$n:$SHA"
  done
  echo
  echo "registry now serves:"
  curl -sf "http://$REGISTRY/v2/_catalog"
  for n in "${IMAGES[@]}"; do
    curl -sf "http://$REGISTRY/v2/$NS/$n/tags/list"
  done
fi
echo
