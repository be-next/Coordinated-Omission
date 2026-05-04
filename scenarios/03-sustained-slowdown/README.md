# Scenario 03 — sustained slowdown

The server's baseline latency ramps **linearly** from 10 ms to 100 ms
between t=20 s and t=50 s, then stays at 100 ms until the end of the
test. No discrete hiccup — just a gradual degradation.

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline (start) | 10 ms     |
| Ramp window      | 20 s → 50 s |
| Baseline (end)   | 100 ms    |

## What this exercises

A single hiccup is an *event* — closed-loop tools sometimes catch its
edge thanks to the swarm of completed-then-recorded responses. A
sustained slowdown is a *regime change*: every request after t=50 s is
slow. Closed-loop tools naturally adjust by issuing fewer requests, but
they *do* see the change in the body of the distribution. The
divergence between closed and open loops is therefore smaller than in
scenario 02, but it shifts to the *body* of the curve, not just the
tail.

## How to run

```sh
make scenario-03
make build-images-03
```
