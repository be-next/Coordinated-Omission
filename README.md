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

| Scenario              | Status | What it shows                                     |
|-----------------------|--------|---------------------------------------------------|
| 01-healthy            | TODO   | Closed and open loops agree when the server is OK |
| 02-single-hiccup      | MVP    | One 1 s stall at t=30 s — the canonical case      |
| 03-sustained-slowdown | TODO   | Progressive degradation                           |
| 04-gc-pauses          | TODO   | Recurring short pauses                            |
| 05-saturation         | TODO   | Target rate exceeds capacity                      |

| Load tool | Default model        | CO-aware? | Status |
|-----------|----------------------|-----------|--------|
| ab        | closed loop          | no        | MVP    |
| Vegeta    | open (constant rate) | yes       | MVP    |
| wrk       | closed loop          | no        | TODO   |
| wrk2      | open (constant rate) | yes       | wired but unbuilt on Apple Silicon (see below) |
| hey       | closed loop          | no        | TODO   |
| k6        | depends on executor  | configurable | TODO |
| JMeter    | closed loop (default)| configurable | TODO |

## Prerequisites

The MVP needs:

- `go` 1.22+ (to build the server) — `brew install go`
- `ab` (Apache Bench) — ships with macOS, also `apt-get install apache2-utils`
- `vegeta` — `go install github.com/tsenart/vegeta/v12@latest`
  (binary lands in `$HOME/go/bin/vegeta`; the runner finds it there even
  if `$HOME/go/bin` is not on `PATH`)
- `python3` 3.10+ — `make setup` creates a local venv and pip-installs
  matplotlib and numpy

`wrk2` is supported by the runner in `load-tools/wrk2/` but **does not build
out of the box on Apple Silicon**: the LuaJIT vendored in `giltene/wrk2`
predates arm64. The repository falls back to Vegeta as the open-loop
reference. If you have a working `wrk2` binary, the analysis pipeline picks
it up automatically.

Subsequent scenarios will add `wrk`, `hey`, `k6`, and `jmeter`.

## Reproducing the blog illustrations

```sh
make build-images       # regenerate every SVG/PNG in images/
make publish-blog       # rsync images/ into the idle-ti.me content folder
```

Both targets are explicit on purpose: the blog post does not pull from this
repository at build time. Images are generated, reviewed, then published.

## License

MIT — see `LICENSE`.
