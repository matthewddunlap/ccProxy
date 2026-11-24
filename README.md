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

## Quickstart

```sh
./pipeline/fetch-weights.sh
docker compose build
docker compose up -d cardconjurer filebrowser
docker compose run --rm pipeline render data/decks/single.txt @data/conf/custom.conf
```

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
