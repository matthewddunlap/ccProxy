# AGENT DOING — current work item

## NEXT SESSION, START HERE (2026-11-25, end)

**Nothing in flight.** The e2e-tests item is DONE + verified (see
`AGENT_DONE.md`, "Repeatable e2e + fresh-deploy fixes"): the `init` chown
fix, the `decks/prime.txt` seeding, and the repeatable `scripts/e2e.sh` —
green TWICE on a fresh deploy (`cce2e`, `.216`, published image), no manual
chown/seeding. **Committed locally; PUSH is pending user confirmation**
(handoff rule: confirm before pushing — outward. None of these commits
touch the workflow's `paths` gate — `cardconjurer/**`, `pipeline/**`,
`pins.txt`, the workflow — so a push does NOT re-bake/republish images.)

Next up (TODO order):
1. **Flip the production flow to the new stack** (TODO #1) — the user's
   call; old compose stays up until then. .216's compose `image:` refs
   already point at Docker Hub, so the flip is conf + service restart only.
2. Carried-over follow-ups (TODO #2).

### Sanity-check commands (.216 = `ssh root@172.17.1.216`)
```sh
docker ps --format '{{.Names}}: {{.Status}}'
# old stack 4241-4 | main 5241-4 (:local) | cctest 5341-4 | cce2e 5351-4 (test, 8082 fb)

# Repeatable e2e — from a repo checkout on the docker host, ~4 min:
cd /tmp/cce2e          # existing test copy; or a fresh clone
env E2E_PROJECT=cce2e CC_PORT_1=5351 CC_PORT_2=5352 CC_PORT_3=5353 CC_PORT_4=5354 \
    FILEBROWSER_PORT=8082 E2E_CACHE_SRC=/tmp/ccfresh/data \
    nohup sh scripts/e2e.sh </dev/null > e2e_run.log 2>&1 &   # detached: 120s ssh kills foreground renders
# GREEN: version pins, offline render (809 local-cache prints), cards
# 18d2cdfe…cfc0d3 / 635fcbdf…5fa32a byte-identical, cameo PDF 505,930 B / 1 page.
```
For BYTE-identical card re-runs the stack must be FRESH (stop the app, clear
`data/art` + `data/card_images`, seed both caches) — a stack whose app
carries residue from an interrupted session can emit a different deflate
stream for the same pixels (the script diagnoses this: pixel digest on a
byte mismatch). Details: `bringup.md` (e2e section).
