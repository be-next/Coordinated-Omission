# `co-server` — system under test

A deliberately misbehaving HTTP server. Its only purpose is to be measurable.

## Endpoints

| Path       | Behaviour                                                     |
|------------|---------------------------------------------------------------|
| `/healthy` | Returns `ok` after `baseline-latency`. Never affected by hiccups. Use for sanity checks. |
| `/api`     | Returns `ok` after `baseline-latency`. **Blocked during a scheduled hiccup** — every concurrent request piles up behind the same gate and unblocks together when the pause ends. |

## Flags

| Flag | Default | Meaning |
|------|---------|---------|
| `-addr` | `:8080` | Listen address |
| `-baseline-latency` | `1ms` | Latency added to every response |
| `-hiccup-at` | `0` | When to start the single scheduled hiccup, measured from server start. `0` disables. |
| `-hiccup-duration` | `0` | Duration of the hiccup. Combined with `-hiccup-at`. |

## Build and run

```sh
go build -o co-server .
./co-server -hiccup-at 30s -hiccup-duration 1s
```

## Why a `sync.RWMutex` for the gate?

The gate models a stop-the-world pause as observed by clients: requests
arriving while the gate is held queue up and are released as a burst when
the gate is released. This is the shape that drives the difference between
closed-loop and open-loop measurements. It is *not* a faithful simulation
of a real GC pause (which suspends in-flight work too); it is a faithful
simulation of what the *client* sees.
