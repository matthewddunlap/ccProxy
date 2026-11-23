# ccProxy bring-up & verification

## Build (any host with a docker/podman builder — .216 today)

```sh
git clone git@github.com:matthewddunlap/ccProxy.git
cd ccProxy
./pipeline/fetch-weights.sh          # weights from the pinned Real-ESRGAN releases
docker compose build
```

## First run

```sh
mkdir -p data/decks data/out data/cache
docker compose up -d cardconjurer filebrowser

# smoke: all four ports serve the app
for p in 4241 4242 4243 4244; do curl -fsS "http://localhost:$p/" | grep -o '<title>[^<]*' ; done

# smoke: PUT + HEAD round trip (what the workers do)
curl -fsS -X PUT --data-binary 'hello' http://localhost:4242/local_art/smoke.txt
curl -fsSI  http://localhost:4242/local_art/smoke.txt | head -1
curl -fsS -X DELETE http://localhost:4242/local_art/smoke.txt

# render one small deck (same flags as today's custom.conf)
docker compose run --rm pipeline version
docker compose run --rm pipeline render data/decks/single.txt @data/conf/custom.conf
```

## A/B against the live stack (byte-identity methodology from the AGENT notes)

1. Same deck + same conf through the OLD stack (`.216` 5×nginx + mtgproxy driver).
2. Same deck + same conf through ccProxy (`mtg render …`).
3. Compare every output PNG byte-for-byte (`sha256sum` both sets).
4. `mtg version` output goes into the test record — it names every pinned SHA
   and the exact chromium that rendered, so any future drift is attributable.

If PNGs differ, first suspect **chromium version** (glyph metrics drive the
auto-fit calibrations): pin the old chromium build into the image, or re-run
the `*_calibrate.py` scripts against the new one and re-compare.

## 5→1 nginx collapse: test plan

All five old containers served byte-identical content from the same mounts, so
one container with four listeners is *supposed* to be a no-op. Proving it:

- [ ] static equivalence: `diff` response bodies across old 4241–4244 vs new (a few URLs: index.html, creator JS, one set symbol)
- [ ] PUT + HEAD + GET round trip on each of the 4 ports; file visible in filebrowser
- [ ] concurrency: two `render` runs in parallel against the same origin — no cross-contamination (workers are `--incognito` isolated), both outputs land, correct cards per batch
- [ ] full byte-identity A/B above
- [ ] old five-container compose stays up until all of the pass; flipping is a `--url` in the conf

## Known deltas / follow-ups (deliberate, tracked)

- **X-Upload-Secret**: the client sends it; the (vendored) conf does not
  enforce it — same as today, on a trusted LAN. Hardening is a follow-up.
- **gradio_client** is still installed so the pinned ccAutomator's remote
  upscale path works unchanged; the in-process `--upscale-art` wiring is a
  follow-up code change in ccAutomator (engines + `mtg upscale` are ready).
- **`--decks` / `--workers`** (orchestrator mode, the native run_batches) is a
  follow-up change in ccAutomator; until then `render` takes one decklist and
  you loop externally.
- **run-all** (`mtg render … && mtg pdf …` as one command) once the
  render→pdf handoff contract is pinned down.
- **Quadlet units**: translate this compose.yaml (image + port + volume + env)
  into `.container` units for the quadlet host; same images, same data dir.
