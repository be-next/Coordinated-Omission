# Scenario 01 — healthy run (control)

The same load profile as scenario 02 but **without** any scheduled
hiccup. Its only purpose is to be a control: when the server has no
pathological behaviour, a closed-loop and an open-loop tool should
agree on the latency distribution to within rounding.

If they do agree, the divergence observed in scenario 02 cannot be
attributed to the tools themselves — it has to be a property of the
phenomenon being measured. This is the classic falsification check.

## Profile

| Parameter        | Value     |
|------------------|-----------|
| Test duration    | 60 s      |
| Target rate      | 1 000 rps |
| Baseline latency | 10 ms     |
| Hiccup           | **none**  |

## Expected outcome

Both tools should report essentially identical percentile spectra.
Differences below ~0.5 ms across all percentiles are typical and come
from the loopback connection overhead in `ab` versus the request-pacing
clock in Vegeta.

## How to run

```sh
make scenario-01            # ab + Vegeta against a fresh server, no hiccup
make build-images-01        # render comparison plot to images/01-healthy/
```
