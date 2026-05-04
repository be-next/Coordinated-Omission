# Scenario 01 — healthy run (control)

> Companion material for the article *Coordinated Omission: Why Your
> Latency Numbers Lie* —
> [idle-ti.me/blog/coordinated-omission/](https://idle-ti.me/blog/coordinated-omission/).

This scenario is the **falsification control** for the rest of the
suite. The same load profile as the other scenarios is run against a
server that has *no* injected pathology. Every tool — closed-loop or
open-loop — should report essentially the same latency distribution.

If they all agree here but diverge in scenarios 02–05, the divergence
cannot be a property of the tools. It has to be a property of the
phenomenon being measured. That is the experimental claim of the blog
post, restated as a procedure.

## Profile

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 10 ms     |
| Server pathology | **none**  |

## Server pathology

None. The server runs with the default `-baseline-latency 10ms` and no
pause/ramp/cap flags. Implementation: `server/main.go`.

## Tools exercised

All eight load tools defined in `load-tools/`:

| Closed loop                        | Open loop                                    |
|------------------------------------|-----------------------------------------------|
| `ab`                               | `vegeta`                                     |
| `wrk`                              | `k6` — `constant-arrival-rate` executor      |
| `hey`                              | `JMeter` — *Precise Throughput Timer*        |
| `k6` — `constant-vus` executor     |                                              |
| `JMeter` — default ThreadGroup     |                                              |

The ninth tool — `wrk2` — is wired but does not build on Apple Silicon;
see the repository [README](../../README.md).

## What this scenario demonstrates

Two things:

1. **The eight tools agree on a healthy server.** Differences across
   the percentile spectrum stay within a few milliseconds — typically
   below the resolution that would matter for any production decision.
2. **Therefore the divergence in scenarios 02–05 is real, not
   instrumental.** This is what a control is for.

Concretely, every percentile from p50 to p99.99 lands within ~30 ms
across all eight tools. There is no closed-loop / open-loop split.

## How to run

```sh
make scenario-01            # build, run all eight tools, stop the server
make build-images-01        # render comparison plots into images/01-healthy/
```

Each tool starts and stops its own copy of the server, so the run is
reproducible from a clean state every time.

## Generated images

After `make build-images-01`, four SVGs are written into
`images/01-healthy/`:

| File                                  | Content                                                 |
|---------------------------------------|---------------------------------------------------------|
| `closed-vs-open-percentiles.svg`      | the canonical pair — `ab` vs Vegeta                     |
| `k6-bad-vs-good.svg`                  | the article's worked example — k6 in both modes         |
| `jmeter-bad-vs-good.svg`              | the JMeter equivalent — ThreadGroup vs Throughput Timer |
| `all-tools.svg`                       | all eight tools together                                |

In every plot of this scenario, the curves overlap. That overlap is the
result.
