# Scenario 02 — single hiccup

The canonical case from the blog post: a 60-second test against a server
that stalls for **one second at t=30 s**, then resumes normal operation.

## Profile

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 1 ms      |
| Hiccup start     | t=30 s    |
| Hiccup duration  | 1 000 ms  |

The hiccup is scheduled by the server itself via `-hiccup-at 30s
-hiccup-duration 1s`. The load tools do not need to know about it; the
point of the scenario is precisely that they should *report* it correctly.

## Expected outcome

| Tool   | Reported p99   | Reported p99.9 | Honest? |
|--------|----------------|----------------|---------|
| `ab`   | ~5 ms          | ~50–500 ms     | no — only requests already in flight see the stall |
| `wrk2` | several 100 ms | ~900 ms        | yes — queued requests carry intended-start-time correction |

Numbers above are illustrative; exact values depend on hardware and
configured concurrency. What matters is the *shape* of the difference,
not the digits.

## How to run

```sh
# from the repository root, in two terminals
make run-server                                    # terminal 1: starts the server with the hiccup scheduled
make run-scenario-02                               # terminal 2: launches ab and wrk2 in turn
```

Or scripted, from the repository root:

```sh
make scenario-02                                   # builds, starts server, runs both tools, stops server
```

Raw outputs land in `results/02-single-hiccup/`. The analysis pipeline
turns them into the comparison images in `images/02-single-hiccup/`.
