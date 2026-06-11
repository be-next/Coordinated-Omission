# Scenario 02 — single hiccup

> Companion material for the article *Coordinated Omission: Why Your
> Latency Numbers Lie* —
> [idle-ti.me/blog/coordinated-omission/](https://idle-ti.me/blog/coordinated-omission/).

The canonical case from the blog post. A 60-second test runs against a
server that stalls for **one second at t=30 s**, then resumes normal
operation. Eight load tools probe the run; closed-loop tools
systematically hide the stall, open-loop tools systematically expose
it. The gap at p99 is two orders of magnitude.

## Profile

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 10 ms     |
| Hiccup start     | t=30 s    |
| Hiccup duration  | 1 000 ms  |

## Server pathology

A single 1-second pause is scheduled by the server at `t = 30 s`:

```
co-server -hiccup-at 30s -hiccup-duration 1s
```

Implementation: every `/api` request takes a read-lock on a
`sync.RWMutex`; at t=30 s a goroutine takes the write-lock for one
second. All requests that arrive during the pause queue at the gate
and unblock together when the pause ends — the same shape as a
stop-the-world GC pause from the client side. See `server/main.go`.

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

The structural lie of closed-loop benchmarks under a server slowdown:

- **At p50–p95:** all eight tools agree to within rounding. The body of
  the distribution is unaffected by coordinated omission.
- **At p99:** the divergence appears. Closed-loop tools still report a
  near-baseline latency (~12–19 ms) because only the few requests that
  were in flight at the start of the stall observe it. Open-loop tools
  report a tail latency in the hundreds of milliseconds, reflecting the
  ~1 000 requests that *would have arrived* during the stall in a real
  open workload.
- **At p99.9 the gap widens** (~12–27 ms closed vs ~950 ms open): a
  closed-loop tool records only one stalled sample per virtual user —
  about ten for `ab` — far too few to lift even the 99.9th percentile.
  The two groups reconverge only at p99.99, where the handful of
  stalled samples finally outnumbers the percentile's population.
  Production dashboards watch p99 and p99.9 — exactly where the lie
  lives.

This is the empirical illustration of the article's central claim.

## How to run

```sh
make scenario-02            # build, run all eight tools, stop the server
make build-images-02        # render comparison plots into images/02-single-hiccup/
```

Each tool starts and stops its own copy of the server, so the hiccup
fires at t=30 s relative to the start of *each* runner.

## Expected outcome

| Percentile | closed-loop tools | open-loop tools |
|------------|-------------------|-----------------|
| p50        | ~10–12 ms         | ~10 ms          |
| p95        | ~12–15 ms         | ~10 ms          |
| **p99**    | **~12–19 ms**     | **~400–450 ms** |
| **p99.9**  | **~12–27 ms**     | **~950 ms**     |
| p99.99     | ~1 000 ms         | ~1 000 ms       |

Numbers are illustrative; exact values depend on hardware and tool
configuration. What matters is the *shape* of the difference at p99
between the two groups, not the precise digits.

`wrk` is a borderline case: its `--latency` HDR output reports a tail
much closer to the open-loop tools (~400 ms at p99) despite being
conventionally classified as closed-loop. See the repository
[README](../../README.md).

## Generated images

After `make build-images-02`, six SVGs are written into
`images/02-single-hiccup/`:

| File                                  | Content                                                 |
|---------------------------------------|---------------------------------------------------------|
| `closed-vs-open-percentiles.svg`      | percentile spectrum — `ab` vs Vegeta                    |
| `k6-bad-vs-good.svg`                  | percentile spectrum — k6 in both modes                  |
| `jmeter-bad-vs-good.svg`              | percentile spectrum — JMeter in both modes              |
| `all-tools.svg`                       | percentile spectrum — all eight tools                   |
| `latency-timeline.svg`                | latency vs. time scatter; the 1 s hiccup window is shaded — `ab` shows ~10 stalled samples, Vegeta shows a ~1 000-point queueing wedge |
| `throughput-timeline.svg`             | completed RPS vs. time; the closed-loop curve drops to zero during the hiccup, the open-loop curve drops then bursts above the target rate as the queue drains |

In every percentile plot of this scenario, two clusters of curves
separate sharply at p99: closed-loop tools stay along the baseline,
open-loop tools rise toward the stall duration. The two timeline plots
show *why*: open-loop tools record every queued request, closed-loop
tools record only the few in-flight at the start of the stall.
