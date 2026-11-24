# AGENT DOING — current work item

## IN FLIGHT: GitHub Actions → Docker Hub publication (2026-11-24)

User ruling (recorded in AGENT_OVERVIEW): build via GitHub Actions,
publish PUBLIC to Docker Hub as
`matthewddunlap/ccproxy-{cardconjurer,pipeline}`, `:latest` + `<sha7>`.
Rejected: GHCR (storage), LAN registry on .216 (no .216 builds), and frame
trimming (keep the full frame set).

State:
- Workflow: `ca10995` + YAML fix `fc955c2`. Run #1 failed instantly (YAML
  typo — unquoted `:` in a step name). Run #2 in flight.
- Compose `image:` already points at the Docker Hub names (+ kept `build:`
  so offline local builds still work).
- Abandoned LAN-registry leftovers cleaned from .216 (registry:2 image
  removed, orphaned `ccproxy/*:latest` tags removed, live `:local` images
  untouched); `build.sh` removed from the repo.

NEXT (in order):
1. Confirm run #2 green:
   `curl -s https://api.github.com/repos/matthewddunlap/ccProxy/actions/runs?per_page=1`
2. Pull + `mtg version` from .216 AND .217 (proves delivery; plain HTTPS,
   no daemon config):
   `docker pull matthewddunlap/ccproxy-pipeline:latest`
   `docker run --rm matthewddunlap/ccproxy-pipeline:latest version`
3. Record in AGENT_DONE (run URL + head SHA + pull evidence); update the
   ccproxy-stack memory (publication path).
4. Full render/PDF smokes on .216 happen with the flip (TODO #2, user-gated).

## Context


Quick re-orientation on the live deploy (`.216` = ssh root@172.17.1.216):
```
/conf/ccProxy                       # clone + compose (project name: ccproxy)
conf/ccProxy/data/                  # shared data: decks/, card_images/teaching/,
                                    # out/, art/, scryfall_cache.db,
                                    # centered_text_cache.json
new app:  http://.216:5241-5244     # cardconjurer (1 container, 4 listeners)
old app:  http://.216:4241-4244     # still up, until the flip
filebrowser new: http://.216:8080   # serves conf/ccProxy/data
```
Sanity checks after ANY image change (all from /conf/ccProxy):
```
docker compose run --rm pipeline version                     # pins + chromium
docker compose run --rm pipeline upscale /data/upscale_in.png /data/upscale_out.png \
    --mode fast --model realesrgan-x2                         # torch+engines (CPU ok)
docker compose run --rm pipeline pdf --cameo --paper-type letter \
    --cameo-orientation portrait --png-dir /data/card_images/teaching \
    --deck-list decks/smoke.txt --output-file /data/out/smoke_cameo        # prod layout
docker compose run --rm pipeline render --overwrite --url http://cardconjurer:4242 \
    --image-server http://cardconjurer:4242 @/opt/ccAutomator/custom.conf decks/smoke.txt
```
(A render MUST show "Resolved N local cache print(s)" — if it says
"Cross-referencing … Scryfall result(s)" against the API, the data-dir env
is wrong again: trap #1 in AGENT_OVERVIEW.)
