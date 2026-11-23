# ccProxy pipeline image — one image, three tools behind the `mtg` CLI:
#   render    ccAutomator (decklists -> card PNGs, Selenium + Card Conjurer app)
#   pdf       MtgPng2Pdf  (card PNGs + decklist -> cut-ready print PDF)
#   upscale   Ilaria engines in-process (no server, no Gradio)
#
# All sources pinned to SHAs (see ../pins.txt). `mtg version` prints them.
ARG CCAUTOMATOR_SHA=75677f6ce06ac27bbdc5da1ec6f192c6d4e91be0
ARG MTGPDF_SHA=4bf9b723f3adc294e86b8e3e1cc5e62c39736aa1
ARG ILARIA_SHA=57e887c8e2ef20e99b5d20b8d224851c2d8c4700

FROM docker.io/python:3.11-slim-bookworm

# ARGs do not cross the FROM boundary — re-declare to use them in this stage
# (override at build time still works: --build-arg CCAUTOMATOR_SHA=...)
ARG CCAUTOMATOR_SHA
ARG MTGPDF_SHA
ARG ILARIA_SHA

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DATA_DIR=/data

# chromium + matching chromedriver (PATH-based, as ccAutomator expects)
# + fonts for both chromium canvas text and PIL text rendering.
# NOTE: glyph calibrations (pt/title/type tables in ccAutomator) were measured
# against a specific chromium — verify the A/B in ../bringup.md before bumping.
RUN apt-get update && apt-get install -y --no-install-recommends \
        chromium chromium-driver curl ca-certificates fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# --- pinned sources --------------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/ccAutomator /opt/MtgPng2Pdf /opt/ilaria /opt/mtg-tools /data; \
    curl -fsSL "https://codeload.github.com/matthewddunlap/ccAutomator/tar.gz/${CCAUTOMATOR_SHA}" \
        | tar -xz -C /opt/ccAutomator --strip-components=1; \
    curl -fsSL "https://codeload.github.com/matthewddunlap/MtgPng2Pdf/tar.gz/${MTGPDF_SHA}" \
        | tar -xz -C /opt/MtgPng2Pdf --strip-components=1; \
    tmp="$(mktemp -d)"; \
    curl -fsSL "https://codeload.github.com/TheStingerX/Ilaria-Upscaler/tar.gz/${ILARIA_SHA}" \
        | tar -xz -C "$tmp"; \
    d="$(ls -d "$tmp"/*/ )"; \
    cp "${d}engines.py" "${d}bootstrap.py" /opt/ilaria/; \
    rm -rf "$tmp"

# --- python deps -----------------------------------------------------------
# ORDER MATTERS: torch FIRST, from the CPU wheel index. spandrel depends on
# torch; if it is installed first from the default PyPI index, pip pulls the
# CUDA build + nvidia-* wheels (multi-GB, wrong device for these hosts).
RUN pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu torch torchvision
# then the rest from PyPI (torch already satisfied -> not re-downloaded);
# incl. gradio_client so the pinned ccAutomator's remote-upscale path still works
RUN pip install --no-cache-dir \
        -r /opt/ccAutomator/requirements.txt \
        reportlab numpy spandrel spandrel-extra-arches

# upscaling weights — populated by fetch-weights.sh before build (.keep guards COPY)
COPY models/ /opt/ilaria/models/

# --- mtg CLI ----------------------------------------------------------------
COPY mtg /usr/local/bin/mtg
COPY upscale.py /opt/mtg-tools/upscale.py
RUN chmod +x /usr/local/bin/mtg

# Reproducibility record: image + every pinned SHA + the chromium that rendered.
RUN set -eux; \
    printf '{"image":"ccproxy-pipeline","ccautomator":"%s","mtgpng2pdf":"%s","ilaria_engines":"%s","chromium":"%s"}\n' \
        "${CCAUTOMATOR_SHA}" "${MTGPDF_SHA}" "${ILARIA_SHA}" "$(chromium --version | awk '{print $2}')" \
        > /opt/mtg-version.json

WORKDIR /data
ENTRYPOINT ["mtg"]
