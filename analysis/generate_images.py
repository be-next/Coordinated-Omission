#!/usr/bin/env python3
"""Render the comparison images for a scenario.

For the MVP only scenario 02-single-hiccup is supported. The script reads
ab and wrk2 outputs from results/<scenario>/, computes percentile spectra,
and writes SVG illustrations to images/<scenario>/.

If real outputs are missing the script falls back to a labelled synthetic
distribution so that the rendering pipeline is always exercisable. Synthetic
images are clearly marked in their title and filename.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import matplotlib.pyplot as plt


REPO_ROOT = Path(__file__).resolve().parent.parent

# Percentile grid used for every comparison plot. Heavy at the tail because
# coordinated omission is a tail phenomenon — the body of the distribution
# is uninteresting.
PERCENTILES = np.array([
    0.0, 0.10, 0.20, 0.30, 0.40, 0.50,
    0.60, 0.70, 0.75, 0.80, 0.85, 0.90,
    0.95, 0.97, 0.98, 0.99,
    0.995, 0.999, 0.9995, 0.9999, 0.99999,
])


@dataclass
class PercentileSeries:
    label: str
    percentiles: np.ndarray  # in [0, 1)
    latencies_ms: np.ndarray
    synthetic: bool = False


def parse_ab_csv(path: Path) -> PercentileSeries | None:
    """ab -e produces a CSV: Percentage served, Time in ms (one line per integer percentile)."""
    if not path.exists():
        return None
    pct, lat = [], []
    with path.open() as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        for row in reader:
            if len(row) < 2:
                continue
            try:
                p = float(row[0]) / 100.0
                t = float(row[1])
            except ValueError:
                continue
            pct.append(p)
            lat.append(t)
    if not pct:
        return None
    return PercentileSeries("ab (closed loop)", np.array(pct), np.array(lat))


_HDR_LINE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s")


def _parse_hdr(path: Path, value_unit_to_ms: float, label: str) -> PercentileSeries | None:
    """Parse a tab- or whitespace-separated HDR-style percentile dump.

    First column is the latency in some unit (multiplied by ``value_unit_to_ms``
    to get milliseconds), second column is the percentile in [0, 1].
    """
    if not path.exists():
        return None
    pct, lat = [], []
    with path.open() as f:
        next(f, None)  # header
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            try:
                v = float(parts[0])
                p = float(parts[1])
            except ValueError:
                continue
            pct.append(p)
            lat.append(v * value_unit_to_ms)
    if not pct:
        return None
    return PercentileSeries(label, np.array(pct), np.array(lat))


def parse_wrk2_hdr(path: Path) -> PercentileSeries | None:
    # wrk2's percentile() returns microseconds.
    return _parse_hdr(path, 1.0 / 1000.0, "wrk2 (open loop, constant rate)")


def parse_vegeta_hdr(path: Path) -> PercentileSeries | None:
    # Vegeta's hdrplot reporter emits the value column in milliseconds.
    return _parse_hdr(path, 1.0, "Vegeta (open loop, constant rate)")


def parse_wrk2_txt(path: Path) -> PercentileSeries | None:
    """Fallback parser for wrk2 stdout when --latency is set.

    Looks for the ``Detailed Percentile spectrum`` block, then collects the
    'value percentile total 1/(1-percentile)' rows.
    """
    if not path.exists():
        return None
    text = path.read_text(errors="ignore")
    in_block = False
    pct, lat = [], []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("Detailed Percentile spectrum"):
            in_block = True
            continue
        if not in_block:
            continue
        if stripped.startswith("#") or stripped.startswith("-"):
            continue
        m = _HDR_LINE.match(line)
        if not m:
            if pct and stripped == "":
                break
            continue
        try:
            value_ms = float(m.group(1))
            percentile = float(m.group(2))
        except ValueError:
            continue
        pct.append(percentile)
        lat.append(value_ms)
    if not pct:
        return None
    return PercentileSeries("wrk2 (open loop, constant rate)", np.array(pct), np.array(lat))


# The synthetic distributions intentionally mirror the parameters in the
# Makefile (10 ms baseline, 1 s hiccup, 1 000 rps for 60 s). Keeping these
# in sync with the runners is what lets a "mixed" plot place the synthetic
# series on the same body as the measured one.
_SYNTH_BASELINE_MS = 10.0
_SYNTH_TOTAL = 60_000
_SYNTH_HICCUP_MS = 1_000.0


def synthetic_closed_loop(concurrency: int = 10) -> PercentileSeries:
    """Closed-loop tool's view of the canonical scenario.

    With C concurrent virtual users, only the C requests in flight at the
    instant of the stall observe latency near the stall duration. The rest
    of the run sits at baseline, with a small jitter.
    """
    rng = np.random.default_rng(42)
    baseline = _SYNTH_BASELINE_MS + rng.gamma(shape=2.0, scale=1.0, size=_SYNTH_TOTAL - concurrency)
    stalled = rng.uniform(_SYNTH_HICCUP_MS - 50, _SYNTH_HICCUP_MS, size=concurrency)
    samples = np.sort(np.concatenate([baseline, stalled]))
    lat = _percentile_values(samples, PERCENTILES)
    return PercentileSeries("ab (closed loop)", PERCENTILES.copy(), lat, synthetic=True)


def synthetic_open_loop() -> PercentileSeries:
    """Open-loop tool's view of the same run.

    During the 1 s stall, ~1 000 requests are scheduled and queue up. Each
    one's reported latency includes its time in the queue — the
    intended-start-time correction — and decays linearly as the server
    catches up after the pause.
    """
    rng = np.random.default_rng(43)
    queued = int(_SYNTH_HICCUP_MS)
    baseline = _SYNTH_BASELINE_MS + rng.gamma(shape=2.0, scale=1.0, size=_SYNTH_TOTAL - queued)
    queue_lat = np.linspace(_SYNTH_HICCUP_MS, _SYNTH_BASELINE_MS, queued) + rng.normal(0, 5.0, queued)
    queue_lat = np.clip(queue_lat, _SYNTH_BASELINE_MS, None)
    samples = np.sort(np.concatenate([baseline, queue_lat]))
    lat = _percentile_values(samples, PERCENTILES)
    return PercentileSeries("wrk2 (open loop, constant rate)", PERCENTILES.copy(), lat, synthetic=True)


def _percentile_values(sorted_samples: np.ndarray, percentiles: np.ndarray) -> np.ndarray:
    n = len(sorted_samples)
    idx = np.minimum((percentiles * n).astype(int), n - 1)
    return sorted_samples[idx]


def plot_comparison(series: list[PercentileSeries], out_path: Path, title: str) -> None:
    fig, ax = plt.subplots(figsize=(9, 5.5), dpi=120)
    for s in series:
        x = 1.0 / np.maximum(1.0 - s.percentiles, 1e-6)
        label = s.label + ("  [synthetic]" if s.synthetic else "  [measured]")
        ax.plot(x, s.latencies_ms, marker="o", linewidth=1.6, markersize=4, label=label)

    n_synth = sum(1 for s in series if s.synthetic)
    if n_synth == len(series):
        subtitle = "synthetic data"
    elif n_synth == 0:
        subtitle = "measured data"
    else:
        subtitle = "mixed: measured + synthetic"

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel(r"$\dfrac{1}{1-\mathrm{percentile}}$    (50% = 2,  99% = 100,  99.9% = 1000)")
    ax.set_ylabel("latency (ms)")
    ax.set_title(f"{title}\n{subtitle}")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(loc="upper left", framealpha=0.9)

    xticks = [1, 2, 10, 100, 1_000, 10_000, 100_000]
    xlabels = ["0%", "50%", "90%", "99%", "99.9%", "99.99%", "99.999%"]
    ax.set_xticks(xticks)
    ax.set_xticklabels(xlabels)

    fig.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)
    print(f"[images] wrote {out_path.relative_to(REPO_ROOT)}")


def render_scenario_02(mode: str) -> int:
    results_dir = REPO_ROOT / "results" / "02-single-hiccup"
    images_dir = REPO_ROOT / "images" / "02-single-hiccup"

    if mode != "synthetic":
        ab_series = parse_ab_csv(results_dir / "ab" / "percentiles.csv")
        # Prefer Vegeta when available; fall back to wrk2 if the user has
        # one but not the other.
        open_series = (
            parse_vegeta_hdr(results_dir / "vegeta" / "vegeta.hdr")
            or parse_wrk2_hdr(results_dir / "wrk2" / "wrk2.hdr")
            or parse_wrk2_txt(results_dir / "wrk2" / "wrk2.txt")
        )
    else:
        ab_series = None
        open_series = None

    if ab_series is None and mode != "real":
        ab_series = synthetic_closed_loop()
    if open_series is None and mode != "real":
        open_series = synthetic_open_loop()

    if ab_series is None or open_series is None:
        print("[images] missing real data; rerun with --mode auto or run the scenario first", file=sys.stderr)
        return 1

    n_synth = sum(1 for s in (ab_series, open_series) if s.synthetic)
    suffix = {0: "", 1: "-mixed", 2: "-synthetic"}[n_synth]
    plot_comparison(
        [ab_series, open_series],
        images_dir / f"closed-vs-open-percentiles{suffix}.svg",
        "Single 1 s hiccup — closed loop vs. open loop",
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", default="02-single-hiccup",
                        help="scenario identifier (only 02-single-hiccup is supported in the MVP)")
    parser.add_argument("--mode", choices=["real", "synthetic", "auto"], default="auto",
                        help="real: only use measured data. synthetic: only use the canned distribution. "
                             "auto (default): use measured data when present, fall back to synthetic.")
    args = parser.parse_args()

    if args.scenario != "02-single-hiccup":
        print(f"[images] scenario {args.scenario} not implemented yet", file=sys.stderr)
        return 2
    return render_scenario_02(args.mode)


if __name__ == "__main__":
    sys.exit(main())
