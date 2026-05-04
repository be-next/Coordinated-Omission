# Scenario 05 — saturation

> Companion material for the article *Coordinated Omission: Why Your
> Latency Numbers Lie* —
> [idle-ti.me/blog/coordinated-omission/](https://idle-ti.me/blog/coordinated-omission/).

This scenario isolates a **capacity wall**: the server enforces a
maximum number of concurrent in-flight requests via a semaphore. Once
the load tools push past that ceiling, every additional request waits
its turn. Unlike scenarios 02–04 (which inject *transient* slowdowns),
saturation is a *sustained* mismatch between intended rate and
achievable rate.

The default profile keeps the cap **non-binding** so the test produces
a healthy-looking distribution; the README below shows how to override
the cap to actually saturate.

## Profile

| Parameter        | Value      |
|------------------|------------|
| Test duration    | 60 s       |
| Target rate      | 1 000 rps  |
| Baseline latency | 10 ms      |
| Capacity (cap)   | 500 in-flight |

At baseline, by Little's law, **average in-flight = target rate ×
latency = 1 000 × 0.010 s = 10**. The default cap of 500 sits well
above that figure, so it never bites. This is on purpose: the default
is the *safe* regime, where the cap exists but does not constrain.

## Server pathology

A counting semaphore implemented as a buffered channel. Each `/api`
handler reserves one slot before processing, releases it after:

```
co-server -max-concurrency 500
```

Implementation in `server/main.go`.

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

### Default profile (cap = 500, non-binding)

All eight tools agree to within ~5 ms across the spectrum. The cap
exists but never constrains the run. This is the **boring case** —
useful precisely because it shows that a generous capacity ceiling
does not, by itself, perturb the measurement. Saturation only matters
when the cap is *binding*.

### Saturated profile (cap below the natural in-flight count)

To force saturation, drop the cap below `target_rate × baseline`:

```sh
# Capacity = 5 in-flight ⇒ ~500 rps achievable. Target 1 000 rps is
# 2× capacity. Closed-loop tools rate-down to 500 rps and report
# healthy latencies. Open-loop tools refuse to slow down, accumulate
# a queue that grows ~500 rps each second, and report runaway tail
# latency until they hit their request timeout.
make scenario-05 SERVER_FLAGS='-max-concurrency 5'
make build-images-05
```

Any value of `max-concurrency` below `target_rate × baseline_latency`
saturates the server. Vegeta's runner uses `-timeout 5s`, so deep
queueing materialises as a wave of timeouts in the open-loop tools —
which is itself part of the lesson: **the open-loop measurement of a
saturated system is dominated by the timeout policy, not by the system
under test.**

## How to run

```sh
make scenario-05            # default: non-binding cap, all tools agree
make build-images-05

# Or saturate explicitly:
make scenario-05 SERVER_FLAGS='-max-concurrency 5'
make build-images-05
```

## Expected outcome

### Default profile

| Percentile | All eight tools |
|------------|-----------------|
| p50        | ~10–13 ms       |
| p99        | ~12–19 ms       |
| p99.9      | ~13–27 ms       |

### Saturated profile (`-max-concurrency 5`)

Closed-loop tools converge on a uniform ~20 ms p99 (queue wait +
processing). Open-loop tools degrade catastrophically toward the
`-timeout 5s` ceiling. The distance between the two groups is no
longer a *factor* — it is a *separation of regimes*.

## Generated images

After `make build-images-05`, four SVGs are written into
`images/05-saturation/`:

| File                                  | Content                                                 |
|---------------------------------------|---------------------------------------------------------|
| `closed-vs-open-percentiles.svg`      | the canonical pair — `ab` vs Vegeta                     |
| `k6-bad-vs-good.svg`                  | the article's worked example — k6 in both modes         |
| `jmeter-bad-vs-good.svg`              | the JMeter equivalent — ThreadGroup vs Throughput Timer |
| `all-tools.svg`                       | all eight tools together                                |

The committed images correspond to the **default (non-binding) profile**
— curves overlap across the spectrum. Re-render after a saturated run
to see the divergence.
