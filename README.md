# Coordinated Omission — companion repository

Reproducible material for the blog post
[*Coordinated Omission: Why Your Latency Numbers Lie*](https://idle-ti.me/blog/coordinated-omission/).

The repository ships:

- a deliberately misbehaving HTTP server (the *system under test*) whose pauses
  and slowdowns are scriptable;
- a set of **scenarios** that reproduce coordinated-omission failure modes;
- a set of **load-tool runners** (some closed-loop, some open-loop) that probe
  each scenario;
- an **analysis** pipeline that turns raw HDR/CSV outputs into the SVG/PNG
  illustrations used in the blog post.

The code exists so that any reader can clone the repository, run a single
command, and watch the same load profile produce two wildly different latency
reports depending on whether the load tool coordinates with the server or not.

## Quick start

```sh
make mvp                       # build the server, run the canonical scenario,
                               # produce the comparison images
open images/02-single-hiccup/  # inspect the result
```

## Layout

```
server/                     Go HTTP server, hiccup is scheduled by query string
scenarios/                  one folder per scenario, holds run scripts and notes
  02-single-hiccup/         the canonical case from the blog post
load-tools/                 one folder per load tool (ab, wrk2, ...)
analysis/                   Python scripts that parse results and render images
images/                     versioned, generated illustrations (one folder per scenario)
results/                    raw outputs of the most recent run (gitignored)
```

## Status

The repository is built up incrementally. The MVP demonstrates the canonical
case end-to-end with two load tools.

| Scenario              | Status | What it shows                                                          |
|-----------------------|--------|------------------------------------------------------------------------|
| 01-healthy            | done   | Closed and open loops agree when the server is OK                      |
| 02-single-hiccup      | done   | One 1 s stall at t=30 s — the canonical case                           |
| 03-sustained-slowdown | done   | Baseline ramps 10 ms → 100 ms between t=20 s and t=50 s                |
| 04-gc-pauses          | done   | 200 ms gate-hold every 10 s (six pauses across the test)               |
| 05-saturation         | done   | Server has a concurrency cap; default cap is non-binding (see scenario README for the saturated profile) |

| Load tool                                  | Default model              | CO-aware? | Status |
|--------------------------------------------|----------------------------|-----------|--------|
| ab                                         | closed loop                | no        | done   |
| wrk                                        | closed loop                | partial — see below | done   |
| hey                                        | closed loop                | no        | done   |
| Vegeta                                     | open (constant rate)       | yes       | done   |
| k6 — `constant-vus`                        | closed loop                | no        | done   |
| k6 — `constant-arrival-rate`               | open (constant rate)       | yes       | done   |
| JMeter — ThreadGroup (default)             | closed loop                | no        | done   |
| JMeter — Precise Throughput Timer          | open (configurable)        | yes       | done   |
| wrk2                                       | open (constant rate)       | yes       | wired but unbuilt on Apple Silicon |

**About `wrk`.** The Will Glozer fork is conventionally classified as a
closed-loop tool, but its `--latency` HDR output reports a tail that
sits much closer to the open-loop tools than to the other closed-loop
tools — in scenario 02, p99 ≈ 408 ms, in line with Vegeta and k6-good
rather than with ab or k6-bad. The body of the distribution (p50–p90)
behaves like a closed-loop tool. The most plausible explanation is that
wrk's internal timestamping is closer to "intended start time" than its
peers; we have not chased it down further. Treat wrk as a borderline
case rather than a clean negative example.

**A k6 footgun worth knowing.** The `constant-arrival-rate` executor is
only honest if `preAllocatedVUs` and `maxVUs` are large enough to absorb
the slow-down peak. If the pool saturates, k6 reports
`dropped_iterations` and silently *omits* the queued requests —
partially reintroducing coordinated omission while *advertising* an
open-loop model. The default `script.js` in `load-tools/k6-good/`
pre-allocates 1 500 VUs with a ceiling of 5 000 to be safe at 1 000 rps
across a 1 s stall.

## Prerequisites

The MVP needs:

- `go` 1.22+ (to build the server) — `brew install go`
- `ab` (Apache Bench) — ships with macOS, also `apt-get install apache2-utils`
- `vegeta` — `go install github.com/tsenart/vegeta/v12@latest`
  (binary lands in `$HOME/go/bin/vegeta`; the runner finds it there even
  if `$HOME/go/bin` is not on `PATH`)
- `k6` 0.50+ — `brew install k6`
- `wrk` — `brew install wrk`
- `hey` — `brew install hey`
- `jmeter` 5.6+ — `brew install jmeter`
- `python3` 3.10+ — `make setup` creates a local venv and pip-installs
  matplotlib and numpy

`wrk2` is supported by the runner in `load-tools/wrk2/` but **does not build
out of the box on Apple Silicon**: the LuaJIT vendored in `giltene/wrk2`
predates arm64. The repository falls back to Vegeta as the open-loop
reference. If you have a working `wrk2` binary, the analysis pipeline picks
it up automatically.

Subsequent scenarios will exercise sustained slowdowns, recurring GC
pauses, and saturation regimes (see status table above).

## Reproducing the blog illustrations

```sh
make build-images       # regenerate every SVG/PNG in images/
make publish-blog       # rsync images/ into the idle-ti.me content folder
```

Both targets are explicit on purpose: the blog post does not pull from this
repository at build time. Images are generated, reviewed, then published.

## License

MIT — see `LICENSE`.
