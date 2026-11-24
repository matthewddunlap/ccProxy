# AGENT DOING — current work item

## NEXT SESSION, START HERE (2026-11-24)

**Topic: GitHub Actions + container registry for the images** (user will
drive the discussion). Everything needed to start is in:
`AGENT_TODO.md` #1 (constraints) + `AGENT_OVERVIEW.md` (rulings + traps) +
`bringup.md` (how to verify anything end-to-end). Nothing is in flight.

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
