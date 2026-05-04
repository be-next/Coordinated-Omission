# Scenario 04 — recurring GC pauses

The server holds the gate for **200 ms every 10 s**. Six pauses fit in
a 60-second test. Each pause is an order of magnitude shorter than the
hiccup of scenario 02, but they recur.

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 10 ms     |
| Pause every      | 10 s      |
| Pause duration   | 200 ms    |

## What this exercises

200 ms × 1 000 rps × 6 occurrences = **~1 200 queued requests** during
the test. Open-loop tools spread these across p99–p99.5; closed-loop
tools record only the few requests in flight at the start of each
pause. The plot of scenario 04 is what you would see in production
behind a JVM that GC-pauses for 200 ms every minute under sustained
load — a *flatter* tail than scenario 02 but with much more area under
the curve.

## How to run

```sh
make scenario-04
make build-images-04
```
