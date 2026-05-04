# Scenario 05 — saturation

The server is capped at **500 concurrent in-flight requests** while the
load tools target **1 000 rps**. Every request beyond the cap waits its
turn at the semaphore — the server has hit a hard capacity wall.

| Parameter        | Value      |
|------------------|------------|
| Test duration    | 60 s       |
| Target rate      | 1 000 rps  |
| Baseline latency | 10 ms      |
| Capacity         | 500 in-flight |

**About the default profile.** At baseline, 1 000 rps × 10 ms ≈
**10 in-flight** on average (Little's law) — well below the cap of 500.
With the default settings *the server is never saturated*, and the
recorded distribution looks like a healthy run. This is on purpose: the
default is the safe regime, where the cap is an *upper bound* and not a
binding constraint.

To actually saturate, drop the cap below the baseline in-flight count:

```sh
# Force capacity = 500 rps so target = 2× capacity. Open-loop tools will
# accumulate a runaway queue; closed-loop tools will rate-down to 500 rps
# and report a healthy-looking distribution.
make scenario-05 SERVER_FLAGS='-max-concurrency 5'
```

Any value of `max-concurrency` below `target_rate × baseline_latency`
produces a saturated regime. With Vegeta's default `-timeout 5s`,
expect many timeouts in the open-loop measurements — that is part of
the lesson.

## What this exercises (when saturated)

The *opposite* of scenarios 02–04. There is no transient pathology,
only a sustained mismatch between intended rate and achievable rate.
Closed-loop tools report a healthy-looking distribution because the
loop self-throttles; open-loop tools report catastrophic queueing
because they refuse to slow down. **Both pictures are correct for their
respective workload models** — the question is which one matches your
production traffic.

In the *unsaturated* default profile, all eight tools agree to within
~5 ms across the spectrum — the cap exists but never bites.

## How to run

```sh
make scenario-05
make build-images-05
```
