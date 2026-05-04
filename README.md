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
make setup                       # one-time: install Python deps in a local venv
make scenario-02                 # the canonical case: 8 tools against a 1 s hiccup
make build-images-02             # render the four SVGs into images/02-single-hiccup/
open images/02-single-hiccup/    # inspect the result
```

`make help` lists the five scenarios and the matching `build-images`
target for each.

## Layout

```
server/                          Go HTTP server, the system under test;
                                 pathology selected by command-line flags
  main.go                          flags: -hiccup-at, -ramp-*,
                                          -gc-pause-*, -max-concurrency
scenarios/                       one folder per scenario, with its own
                                 README explaining the pathology and the
                                 expected outcome
  01-healthy/                      control: server stays well-behaved
  02-single-hiccup/                one 1 s stall at t=30 s
  03-sustained-slowdown/           baseline ramps 10 ms → 100 ms
  04-gc-pauses/                    200 ms gate-hold every 10 s
  05-saturation/                   server has a hard concurrency cap
load-tools/                      one folder per load tool, with a runner
  ab/        wrk/        hey/      closed-loop tools
  vegeta/    wrk2/                 open-loop tools
  k6-bad/    k6-good/              k6 in both modes (the article's example)
  jmeter-bad/  jmeter-good/        JMeter in both modes
analysis/                        Python scripts that parse results and
                                 render the percentile-distribution plots
  generate_images.py               main entry point
  requirements.txt                 matplotlib + numpy
images/                          versioned, generated illustrations,
                                 one subfolder per scenario, four SVGs each
results/                         raw measurement outputs (gitignored)
Makefile                         orchestration: run, render, publish
```

## Scenarios

Five scenarios; each one isolates a different server pathology so that
the same eight tools can be compared against it. Open the matching
`scenarios/<NN>/README.md` for the full per-scenario story.

| Scenario              | What it shows                                                          |
|-----------------------|------------------------------------------------------------------------|
| 01-healthy            | Control: closed and open loops agree when the server is OK            |
| 02-single-hiccup      | One 1 s stall at t=30 s — the canonical case from the article        |
| 03-sustained-slowdown | Baseline ramps 10 ms → 100 ms between t=20 s and t=50 s              |
| 04-gc-pauses          | 200 ms gate-hold every 10 s (six pauses across the test)              |
| 05-saturation         | Concurrency cap; default cap is non-binding, see scenario for tuning |

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

Run `make check-tools` to see which of the above are present on your
system.

`wrk2` is supported by the runner in `load-tools/wrk2/` but **does not build
out of the box on Apple Silicon**: the LuaJIT vendored in `giltene/wrk2`
predates arm64. The repository falls back to Vegeta as the open-loop
reference. If you have a working `wrk2` binary, the analysis pipeline picks
it up automatically.

## Reproducing the blog illustrations

```sh
make build-images                                          # regenerate every SVG in images/
export BLOG_IMG_DIR=/path/to/your/blog/img                 # one-time
make publish-blog                                          # rsync images/ into that folder
```

`BLOG_IMG_DIR` is read from the environment so the repository never
carries a contributor's local path. You can also pass it inline:

```sh
make publish-blog BLOG_IMG_DIR=/path/to/your/blog/img
```

Both targets are explicit on purpose: the blog post does not pull from
this repository at build time. Images are generated, reviewed, then
published.

## License

MIT — see `LICENSE`.
