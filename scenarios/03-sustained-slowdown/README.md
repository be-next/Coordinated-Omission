# Scenario 03 — sustained slowdown

> Companion material for the article *Coordinated Omission: Why Your
> Latency Numbers Lie* —
> [idle-ti.me/blog/coordinated-omission/](https://idle-ti.me/blog/coordinated-omission/).

This scenario isolates a **gradual degradation**: the server's baseline
latency ramps linearly from 10 ms to 100 ms between t=20 s and t=50 s,
and stays at 100 ms thereafter. There is no discrete event — only a
regime change. The point is to show that coordinated omission is **less
visible** under sustained slowdowns than under hiccups (scenario 02),
and that the divergence migrates from the *tail* into the *body* of
the distribution.

## Profile

| Parameter        | Value         |
|------------------|---------------|
| Test duration    | 60 s          |
| Target rate      | 1 000 rps     |
| Baseline (start) | 10 ms         |
| Ramp window      | 20 s → 50 s   |
| Baseline (end)   | 100 ms        |

## Server pathology

A linear baseline-latency ramp:

```
co-server -ramp-start 20s -ramp-end 50s -ramp-to 100ms
```

Before t=20 s every response sleeps the configured baseline (10 ms).
Between t=20 s and t=50 s the sleep grows linearly toward 100 ms.
After t=50 s every response sleeps 100 ms. Implementation in
`server/main.go` — function `currentBaseline`.

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

A hiccup is an *event*: closed-loop tools hide it at the tail and the
divergence with open-loop is dramatic at p99. A sustained slowdown is
a *regime change*: every request after t=50 s is slow, so closed-loop
tools cannot pretend the system is fine — they end up reporting a
near-100 ms plateau too.

The interesting differences move into the **body of the distribution**:

- **At p50:** closed-loop tools that issue requests as fast as the
  server allows (e.g. `ab`, `hey`) drag toward the 100 ms plateau,
  because the tail of the run dominates their sample. Tools that issue
  requests at a constant *rate* (open-loop, but also some closed-loop
  tools that schedule by iteration count) keep a lower median because
  they keep sampling the early, fast portion.
- **At p99 and beyond:** all eight tools eventually report the 100 ms
  plateau. There is no two-orders-of-magnitude split like in scenario 02.

The scenario is therefore a counter-example to the simplistic narrative
"closed-loop tools always lie." They lie about hiccups; they reflect
sustained regimes (with a different bias).

## How to run

```sh
make scenario-03            # build, run all eight tools, stop the server
make build-images-03        # render comparison plots into images/03-sustained-slowdown/
```

## Expected outcome

| Percentile | `ab`/`hey` (closed) | `k6 constant-vus` / JMeter ThreadGroup | Vegeta / `k6 const-arr-rate` / JMeter Timer |
|------------|---------------------|------------------------------------------|----------------------------------------------|
| p50        | ~100 ms             | ~12 ms                                   | ~42 ms                                       |
| p90        | ~102 ms             | ~65 ms                                   | ~100 ms                                      |
| p99        | ~103 ms             | ~102 ms                                  | ~100 ms                                      |

The split is between *iteration-counted* closed-loop tools (`ab` runs
60 000 requests, regardless of duration → tail-dominated) and
*duration-bounded* tools (k6, JMeter run for 60 seconds → fairer
average). Open-loop tools sit in the middle.

## Generated images

After `make build-images-03`, six SVGs are written into
`images/03-sustained-slowdown/`:

| File                                  | Content                                                 |
|---------------------------------------|---------------------------------------------------------|
| `closed-vs-open-percentiles.svg`      | percentile spectrum — `ab` vs Vegeta                    |
| `k6-bad-vs-good.svg`                  | percentile spectrum — k6 in both modes                  |
| `jmeter-bad-vs-good.svg`              | percentile spectrum — JMeter in both modes              |
| `all-tools.svg`                       | percentile spectrum — all eight tools                   |
| `latency-timeline.svg`                | latency vs. time scatter; the ramp window is shaded     |
| `throughput-timeline.svg`             | completed RPS vs. time; the ramp shows up as a smooth decay rather than a discontinuity |
