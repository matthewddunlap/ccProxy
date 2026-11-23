#!/usr/bin/env bash
# Populate pipeline/models/ with upscaler weights BEFORE `docker build`.
#
# Source: the pinned Real-ESRGAN release URLs (../pins.txt) — the exact URLs
# engines.py itself would download, so the bytes are canonical by definition.
# Each file's sha256 is recorded in models/SHA256SUMS and re-verified on
# later runs. Default: only the model in use (x2plus). MODELS=all fetches
# the whole fast lane.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p models

declare -A URLS=(
  [x2plus]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth"
  [x4plus]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
  [anime]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"
)
WANT="${MODELS:-x2plus}"
[ "$WANT" = "all" ] && WANT="x2plus x4plus anime"

for m in $WANT; do
  f="${URLS[$m]##*/}"
  if [ -f "models/$f" ] && grep -q "^.*  $f\$" models/SHA256SUMS 2>/dev/null; then
    echo "   = models/$f present + verified"
    continue
  fi
  echo ">> fetching $f"
  curl -fL --retry 3 -o "models/$f" "${URLS[$m]}"
  ( cd models && sha256sum "$f" | sed "s#models/##" ) >> models/SHA256SUMS
  echo "   + models/$f  ($(du -h "models/$f" | cut -f1))"
done

echo "weights ready:"
ls -la models/
