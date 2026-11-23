# Card Conjurer — static app + PUT-capable nginx, baked to the exact commit
# running on 172.17.1.216 today (see ../pins.txt).
#
# The ONLY local modification of the upstream project (docker/app.override.conf
# from the .216 clone) is now owned by this repo as ./nginx.conf.
ARG CC_SHA=9e61e7ab1c62774c97421958207cd018ab367bf6

# Exact image id running today on .216 (was nginx:stable-alpine).
FROM docker.io/nginx@sha256:aed99734248e851764f1f2146835ecad42b5f994081fa6631cc5d79240891ec9

RUN set -eux; \
    # busybox wget/tar ship with alpine — no extra packages needed
    wget -qO /tmp/cc.tar.gz "https://codeload.github.com/joshbirnholz/cardconjurer/tar.gz/${CC_SHA}"; \
    mkdir -p /usr/share/nginx/html; \
    tar -xzf /tmp/cc.tar.gz -C /usr/share/nginx/html --strip-components=1; \
    # launcher desktop binaries are not used by the web app; drop ~30 MB
    rm -f /tmp/cc.tar.gz \
         /usr/share/nginx/html/launcher-linux \
         /usr/share/nginx/html/launcher-macos \
         /usr/share/nginx/html/launcher.exe; \
    # render output dir (bound to host ./data/local_art in compose)
    mkdir -p /usr/share/nginx/html/local_art

COPY nginx.conf /etc/nginx/nginx.conf

# One container replaces the five on .216 (4241-4244 were separate nginx
# containers serving byte-identical content; see ../bringup.md test plan).
EXPOSE 4241 4242 4243 4244
