# Scenario 04 — recurring GC pauses

> Companion material for the article *Coordinated Omission: Why Your
> Latency Numbers Lie* —
> [idle-ti.me/blog/coordinated-omission/](https://idle-ti.me/blog/coordinated-omission/).

This scenario isolates a **recurring** pathology: the server holds the
gate for **200 ms every 10 s**, so six pauses fit into a 60-second
test. Each individual pause is an order of magnitude shorter than the
hiccup of scenario 02, but the recurrence accumulates — closed-loop
tools eventually surface the pauses too, just much later in the
percentile spectrum than open-loop tools do.

## Profile

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 10 ms     |
| Pause every      | 10 s      |
| Pause duration   | 200 ms    |
| Total pauses     | 6         |

## Server pathology

A goroutine takes the gate's write-lock periodically:

```
co-server -gc-pause-every 10s -gc-pause-duration 200ms
```

Like scenario 02 the pauses model a stop-the-world GC pause as
observed by the client. Implementation in `server/main.go`.

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

The arithmetic of the pauses:

- **6 pauses × 200 ms × 1 000 rps = ~1 200 affected requests.**
- Out of 60 000 requests, that is **2 %** of the sample — so divergence
  shows up cleanly between **p98 and p99.9**.
- At p99 the closed-loop tools still report ~12 ms (the pauses are
  hidden by their own self-throttling), while open-loop tools report
  ~115 ms (about half the pause duration on average).
- At p99.9 every tool finally surfaces the 200 ms plateau because the
  cumulative count of stalled samples exceeds the threshold.

This is a more realistic production picture than scenario 02: many
real-world pathologies are not single 1-second hiccups but recurring
sub-second pauses. The scenario shows that coordinated omission is
*not* limited to dramatic hiccups — it consistently hides recurring
short pauses too, and the lie is only resolved deeper in the tail.

## How to run

```sh
make scenario-04            # build, run all eight tools, stop the server
make build-images-04        # render comparison plots into images/04-gc-pauses/
```

## Expected outcome

| Percentile | closed-loop tools | open-loop tools |
|------------|-------------------|-----------------|
| p50        | ~11–12 ms         | ~10 ms          |
| p95        | ~12–13 ms         | ~10 ms          |
| **p99**    | **~12–19 ms**     | **~115 ms**     |
| p99.5      | ~13 ms (some), ~210 ms (`ab`/`wrk`) | ~165 ms |
| p99.9      | ~200 ms           | ~200 ms         |

`ab` and `wrk` cross over earlier than the other closed-loop tools
because their lower issue rate per VU means proportionally more of
their samples land inside the pauses.

## Generated images

After `make build-images-04`, four SVGs are written into
`images/04-gc-pauses/`:

| File                                  | Content                                                 |
|---------------------------------------|---------------------------------------------------------|
| `closed-vs-open-percentiles.svg`      | the canonical pair — `ab` vs Vegeta                     |
| `k6-bad-vs-good.svg`                  | the article's worked example — k6 in both modes         |
| `jmeter-bad-vs-good.svg`              | the JMeter equivalent — ThreadGroup vs Throughput Timer |
| `all-tools.svg`                       | all eight tools together                                |
