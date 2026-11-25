# ccProxy

The MTGO decklist → rendered card images → cut-ready print PDF pipeline,
packaged as OCI containers you can spin up anywhere (docker compose today,
quadlet next, NixOS containers after).

**Two daemons, one job image, one data directory.**

| Piece | What it is | Where it comes from |
|---|---|---|
| `cardconjurer` | 1 nginx container (ports 4241–4244) serving the Card Conjurer static app with PUT upload | `joshbirnholz/cardconjurer` @ pinned SHA + `cardconjurer/nginx.conf` (your PUT conf, now under git) |
| `filebrowser` | image browser for the rendered cards | `gtstef/filebrowser`, digest-pinned (freezes the live `beta` tag) |
| `pipeline` | one image, one CLI (`mtg`): **render** (ccAutomator), **pdf** (MtgPng2Pdf), **upscale** (Ilaria engines in-process) | your two repos @ pinned SHAs + `TheStingerX/Ilaria-Upscaler` engines @ pinned SHA + Real-ESRGAN weights |

Everything external is **pinned by SHA/digest** in `pins.txt` and baked into
`mtg version` — if an upstream project disappears, the built images are
unaffected; if you ever need to patch one, that's the fork moment.

## Quickstart (pull & run — the normal path)

Images are published to Docker Hub (public): `matthewddunlap/ccproxy-{cardconjurer,pipeline}`.
**No setup steps** — the one-shot `init` service seeds the filebrowser
config, creates the data dirs, and fixes the data-dir permissions, so
`up -d` just works:

```sh
git clone https://github.com/matthewddunlap/ccProxy.git && cd ccProxy
docker compose up -d                      # (or: podman compose up -d)

printf 'Forest\nBrainstorm\nBrainstorm\n' > data/decks/mydeck.txt   # your deck

docker compose run --rm pipeline render decks/mydeck.txt   # -> card PNGs (data/card_images/teaching/)
docker compose run --rm pipeline pdf    decks/mydeck.txt   # -> production cameo PDF (data/out/mydeck.pdf)
```

Browse/download results at `http://localhost:8080` (filebrowser).

**Knobs** (put them in a `.env` file next to compose.yaml — compose reads it
automatically): `FILEBROWSER_ADMIN_PASSWORD` (default `change-me`),
`CC_PORT_1..4` (app ports, default 4241–4244), `FILEBROWSER_PORT` (default 8080).

**Zero-flag defaults, overridable** (pass the underlying flag to change any):
- `render` uses the **baked production conf** (`/opt/ccAutomator/custom.conf`
  — Seventh + seventhTextless frames, upload mode) and the cardconjurer
  service URL; `render ... @my.conf --url ...` overrides.
- `pdf` is the **production cameo layout** (letter portrait 2×3, "cameo
  matless"); `pdf-plain <flags>` is the full MtgPng2Pdf CLI for the plain
  grid + cut-lines mode.

**Build locally instead of pulling** (only when building your own images):
`./pipeline/fetch-weights.sh && docker compose build` — the weights are the
upscaler's model files (67 MB, SHA256-verified); they are already baked into
the published images, so pull-and-run never needs this step.

## Layout

```
cardconjurer/   Dockerfile + nginx.conf (the vendored PUT conf)
pipeline/       Dockerfile + mtg (wrapper CLI) + upscale.py + fetch-weights.sh + models/
compose.yaml    the whole stack
pins.txt        every source SHA + image digest + weight URL (single source of truth)
bringup.md      build, smoke, A/B byte-identity test plan, known deltas
AGENT_*.md      agent handoff notes (OVERVIEW first: status, rulings, traps;
                TODO/DOING/DONE track the work)
```

## Design notes (the short version)

- The "Card Conjurer instances" were never worker services — they're a static
  site; all rendering happens in the headless chromium the driver controls.
  Five identical nginx containers became one with four listeners.
- Process isolation the pipeline relies on already exists per browser run
  (`--incognito` temp profile), so N parallel workers need no N instances.
- The upscaler is a pure function (image→image); the pinned Ilaria `engines.py`
  runs in-process, so the pipeline has no Gradio/HF-Space dependency.
- The data contract is one directory; addressing goes through flags/env, so the
  supervisor (compose/quadlet/NixOS) is replaceable by definition.
