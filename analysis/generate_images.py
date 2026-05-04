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
import datetime
import json
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


_K6_PCT_RE = re.compile(r"^p\((\d+(?:\.\d+)?)\)$")


def _percentiles_from_samples(samples: np.ndarray, label: str, *, synthetic: bool = False) -> PercentileSeries:
    """Compute the standard percentile grid from a 1-D array of latencies (ms)."""
    sorted_samples = np.sort(samples)
    lat = _percentile_values(sorted_samples, PERCENTILES)
    return PercentileSeries(label, PERCENTILES.copy(), lat, synthetic=synthetic)


def parse_jmeter_csv(path: Path, label: str) -> PercentileSeries | None:
    """Parse the JMeter CSV log: column ``elapsed`` is the latency in ms."""
    if not path.exists():
        return None
    samples: list[float] = []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                samples.append(float(row["elapsed"]))
            except (KeyError, ValueError):
                continue
    if not samples:
        return None
    return _percentiles_from_samples(np.array(samples), label)


def parse_hey_csv(path: Path, label: str) -> PercentileSeries | None:
    """Parse the hey CSV (-o csv): column ``response-time`` is in seconds."""
    if not path.exists():
        return None
    samples: list[float] = []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                samples.append(float(row["response-time"]) * 1000.0)
            except (KeyError, ValueError):
                continue
    if not samples:
        return None
    return _percentiles_from_samples(np.array(samples), label)


_WRK_LATENCY_LINE = re.compile(r"^\s*(\d+(?:\.\d+)?)%\s+([\d\.]+)(us|ms|s|m)\s*$")
_WRK_MAX_LINE = re.compile(r"Latency\s+\S+\s+\S+\s+([\d\.]+)(us|ms|s|m)")


def _wrk_unit_to_ms(unit: str) -> float:
    return {"us": 0.001, "ms": 1.0, "s": 1000.0, "m": 60_000.0}[unit]


def parse_wrk_text(path: Path, label: str) -> PercentileSeries | None:
    """Pull the percentile distribution out of wrk's --latency text output.

    wrk does not produce a machine-readable file; this picks up the
    `Latency Distribution` block (50/75/90/99) plus the `Latency` line max.
    Sparser than the other parsers but still enough to draw a curve.
    """
    if not path.exists():
        return None
    pairs: list[tuple[float, float]] = []
    max_ms: float | None = None
    in_block = False
    for line in path.read_text(errors="ignore").splitlines():
        if "Latency" in line and not in_block:
            m = _WRK_MAX_LINE.search(line)
            if m:
                max_ms = float(m.group(1)) * _wrk_unit_to_ms(m.group(2))
        if "Latency Distribution" in line:
            in_block = True
            continue
        if in_block:
            m = _WRK_LATENCY_LINE.match(line)
            if m:
                pct = float(m.group(1)) / 100.0
                val = float(m.group(2)) * _wrk_unit_to_ms(m.group(3))
                pairs.append((pct, val))
            elif pairs and not line.strip():
                break
    if not pairs:
        return None
    if max_ms is not None:
        pairs.append((0.99999, max_ms))
    pairs.sort()
    pct = np.array([p for p, _ in pairs])
    lat = np.array([l for _, l in pairs])
    return PercentileSeries(label, pct, lat)


def parse_k6_summary(path: Path, label: str) -> PercentileSeries | None:
    """Parse the percentile aggregates produced by `k6 --summary-export`.

    The summary lists discrete keys (min, p(50), p(75), p(90), p(95),
    p(99), p(99.5), p(99.9), p(99.99), max). That is enough density for
    the comparison plot — extreme tails come from the same hiccup samples
    as the other tools.
    """
    if not path.exists():
        return None
    with path.open() as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            return None
    metric = data.get("metrics", {}).get("http_req_duration")
    if not isinstance(metric, dict):
        return None
    pairs: list[tuple[float, float]] = []
    if "min" in metric:
        pairs.append((0.0, float(metric["min"])))
    for key, value in metric.items():
        m = _K6_PCT_RE.match(key)
        if not m:
            continue
        try:
            p = float(m.group(1)) / 100.0
        except ValueError:
            continue
        pairs.append((p, float(value)))
    # Anchor the curve close to 1.0 with the observed max, without using
    # p=1.0 exactly (which would give infinite 1/(1-p) on the log axis).
    if "max" in metric:
        pairs.append((0.99999, float(metric["max"])))
    if not pairs:
        return None
    pairs.sort()
    pct = np.array([p for p, _ in pairs])
    lat = np.array([l for _, l in pairs])
    return PercentileSeries(label, pct, lat)


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
    return PercentileSeries("Vegeta (open loop, constant rate)", PERCENTILES.copy(), lat, synthetic=True)


def synthetic_healthy(label: str, seed: int) -> PercentileSeries:
    """Healthy-server distribution: baseline plus a small gamma jitter.

    Used as the control series for scenario 01 when no measured data is
    available. Both the closed-loop and open-loop synthetic series share
    this shape — the whole point of the control is that they agree.
    """
    rng = np.random.default_rng(seed)
    samples = np.sort(_SYNTH_BASELINE_MS + rng.gamma(shape=2.0, scale=1.0, size=_SYNTH_TOTAL))
    lat = _percentile_values(samples, PERCENTILES)
    return PercentileSeries(label, PERCENTILES.copy(), lat, synthetic=True)


def synthetic_closed_loop_k6() -> PercentileSeries:
    s = synthetic_closed_loop()
    s.label = "k6 constant-vus (closed loop)"
    return s


def synthetic_open_loop_k6() -> PercentileSeries:
    s = synthetic_open_loop()
    s.label = "k6 constant-arrival-rate (open loop)"
    return s


def _percentile_values(sorted_samples: np.ndarray, percentiles: np.ndarray) -> np.ndarray:
    n = len(sorted_samples)
    idx = np.minimum((percentiles * n).astype(int), n - 1)
    return sorted_samples[idx]


# --- Timeseries parsers -------------------------------------------------------
#
# Each parser returns (times_since_test_start_s, latencies_ms) as numpy
# arrays, or None if the source file is missing or empty. Latencies are
# always milliseconds; times are normalised so the first observed sample
# sits at t=0.

Timeseries = tuple[np.ndarray, np.ndarray]


def _normalise_times(t: list[float]) -> np.ndarray:
    arr = np.array(t)
    return arr - arr.min() if len(arr) else arr


def parse_ab_timeseries(path: Path) -> Timeseries | None:
    """ab -g writes a TSV with columns starttime, seconds, ctime, dtime, ttime, wait.

    The second column ('seconds') is the Unix epoch start time of each
    request. ttime is the total time in milliseconds.
    """
    if not path.exists():
        return None
    starts, lats = [], []
    with path.open() as f:
        next(f, None)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            try:
                starts.append(float(parts[1]))
                lats.append(float(parts[4]))
            except ValueError:
                continue
    if not starts:
        return None
    return _normalise_times(starts), np.array(lats)


def parse_hey_timeseries(path: Path) -> Timeseries | None:
    """hey -o csv: response-time (s) and offset (s since test start)."""
    if not path.exists():
        return None
    starts, lats = [], []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                starts.append(float(row["offset"]))
                lats.append(float(row["response-time"]) * 1000.0)
            except (KeyError, ValueError):
                continue
    if not starts:
        return None
    return np.array(starts), np.array(lats)


def parse_k6_timeseries(path: Path) -> Timeseries | None:
    """k6 --out csv: filter on metric_name=http_req_duration. Timestamp in s."""
    if not path.exists():
        return None
    starts, lats = [], []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("metric_name") != "http_req_duration":
                continue
            try:
                starts.append(float(row["timestamp"]))
                lats.append(float(row["metric_value"]))
            except (KeyError, ValueError):
                continue
    if not starts:
        return None
    return _normalise_times(starts), np.array(lats)


def parse_jmeter_timeseries(path: Path) -> Timeseries | None:
    """JMeter results.jtl: timeStamp in milliseconds, elapsed in milliseconds."""
    if not path.exists():
        return None
    starts, lats = [], []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                starts.append(float(row["timeStamp"]) / 1000.0)
                lats.append(float(row["elapsed"]))
            except (KeyError, ValueError):
                continue
    if not starts:
        return None
    return _normalise_times(starts), np.array(lats)


def _iso_to_epoch(s: str) -> float:
    """Robust ISO 8601 → epoch seconds, tolerant to nanosecond precision.

    Vegeta emits timestamps like ``2026-05-04T12:14:32.487997917+02:00``;
    Python's ``datetime.fromisoformat`` accepts up to 6 fractional digits.
    Truncate the fractional part if longer.
    """
    if "." in s:
        i_dot = s.index(".")
        i = i_dot + 1
        while i < len(s) and s[i].isdigit():
            i += 1
        frac = s[i_dot + 1: i][:6]
        s = s[: i_dot + 1] + frac + s[i:]
    return datetime.datetime.fromisoformat(s).timestamp()


def parse_vegeta_timeseries(path: Path) -> Timeseries | None:
    """Vegeta JSONL (``vegeta encode -to=json``): timestamp ISO 8601, latency in ns."""
    if not path.exists():
        return None
    starts, lats = [], []
    with path.open() as f:
        for line in f:
            try:
                obj = json.loads(line)
                starts.append(_iso_to_epoch(obj["timestamp"]))
                lats.append(float(obj["latency"]) / 1e6)
            except (json.JSONDecodeError, KeyError, ValueError):
                continue
    if not starts:
        return None
    return _normalise_times(starts), np.array(lats)


# --- Event annotations --------------------------------------------------------

def _apply_events(ax, events: list[dict] | None) -> None:
    if not events:
        return
    ymin, ymax = ax.get_ylim()
    for ev in events:
        kind = ev.get("kind", "vline")
        color = ev.get("color", "red")
        if kind == "vline":
            ax.axvline(ev["t"], color=color, linestyle=ev.get("linestyle", "--"),
                       linewidth=1.0, alpha=ev.get("alpha", 0.55))
            label = ev.get("label", "")
            if label:
                ax.text(ev["t"], ymax, f" {label}", rotation=90,
                        va="top", ha="left", color=color, fontsize="x-small", alpha=0.9)
        elif kind == "vspan":
            ax.axvspan(ev["t0"], ev["t1"], color=color, alpha=ev.get("alpha", 0.10),
                       linewidth=0)
            label = ev.get("label", "")
            if label:
                ax.text((ev["t0"] + ev["t1"]) / 2, ymax, f"{label}", rotation=0,
                        va="top", ha="center", color=color, fontsize="x-small", alpha=0.9)


def _events_for(scenario: str) -> list[dict]:
    if scenario == "02-single-hiccup":
        return [{"kind": "vspan", "t0": 30.0, "t1": 31.0,
                 "label": "1 s hiccup", "color": "tab:red", "alpha": 0.12}]
    if scenario == "03-sustained-slowdown":
        return [{"kind": "vspan", "t0": 20.0, "t1": 50.0,
                 "label": "baseline ramp 10 → 100 ms", "color": "tab:orange", "alpha": 0.10}]
    if scenario == "04-gc-pauses":
        out = [{"kind": "vline", "t": float(t), "color": "tab:red", "linestyle": "--",
                "alpha": 0.45, "label": "pause" if t == 10 else ""} for t in (10, 20, 30, 40, 50, 60)]
        return out
    return []


# --- Plot helpers -------------------------------------------------------------

def plot_timeline(series_dict: dict[str, Timeseries], out_path: Path,
                  title: str, events: list[dict] | None = None) -> None:
    """Latency-vs-time scatter for a handful of representative tools.

    Each series is sub-sampled to ~5 000 points so the SVG stays under a
    megabyte and the alpha-blended density of the dot cloud reads cleanly.
    """
    # The scatter layer is rasterized so the SVG keeps a vector frame
    # (axes, ticks, legend, title) but inlines the dot cloud as a single
    # PNG. Rendering 20 000 individual <circle> elements bloats the file
    # past 3 MB and looks worse — overlapping dots in vector form do not
    # blend the way PNG alpha-compositing does.
    fig, ax = plt.subplots(figsize=(12.5, 6.5), dpi=120)
    rng = np.random.default_rng(0)
    for label, (t, lat) in series_dict.items():
        if len(t) > 5000:
            idx = np.sort(rng.choice(len(t), 5000, replace=False))
            t, lat = t[idx], lat[idx]
        ax.scatter(t, lat, s=4, alpha=0.35, label=label,
                   edgecolors="none", rasterized=True)
    ax.set_rasterization_zorder(0)
    ax.set_xlabel("time since test start (s)")
    ax.set_ylabel("latency (ms)")
    ax.set_yscale("log")
    ax.set_title(title)
    ax.grid(True, which="both", alpha=0.3)
    _apply_events(ax, events)
    leg = ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1.0),
                    framealpha=0.9, fontsize="small", borderaxespad=0)
    for handle in leg.legend_handles:
        handle.set_alpha(1.0)
        handle.set_sizes([30])
    fig.tight_layout(rect=(0, 0, 0.78, 1.0))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"[images] wrote {out_path.relative_to(REPO_ROOT)}")


def plot_throughput(series_dict: dict[str, Timeseries], out_path: Path,
                    title: str, events: list[dict] | None = None) -> None:
    """Completed-requests-per-second timeline. One line per tool.

    The completion time of each request is start_time + latency. We bin
    completions in 1-second buckets — the chart that results is the
    canonical "what does the throughput meter show during the hiccup?"
    picture: closed-loop drops to zero, open-loop drops too then bursts
    back above the target rate as the queue drains.
    """
    fig, ax = plt.subplots(figsize=(12.5, 6.5), dpi=120)
    max_t = 0.0
    for t, lat in series_dict.values():
        if len(t):
            max_t = max(max_t, float((t + lat / 1000.0).max()))
    bin_edges = np.arange(0, math.ceil(max_t) + 2, 1.0)
    centres = bin_edges[:-1] + 0.5
    for label, (t, lat) in series_dict.items():
        completions = t + lat / 1000.0
        counts, _ = np.histogram(completions, bins=bin_edges)
        ax.plot(centres, counts, label=label, linewidth=1.6, alpha=0.9)
    ax.set_xlabel("time since test start (s)")
    ax.set_ylabel("completed requests per second (1 s bins)")
    ax.set_title(title)
    ax.grid(True, which="major", alpha=0.3)
    _apply_events(ax, events)
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1.0),
              framealpha=0.9, fontsize="small", borderaxespad=0)
    fig.tight_layout(rect=(0, 0, 0.78, 1.0))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)
    print(f"[images] wrote {out_path.relative_to(REPO_ROOT)}")


def plot_comparison(series: list[PercentileSeries], out_path: Path, title: str) -> None:
    # The legend lives outside the plot area, anchored to the right edge.
    # The previous in-plot placement collided with the tail-rising portion
    # of the curves once the open-loop tools climb to ~1 000 ms. Reserving
    # a fixed right gutter ensures the legend never covers data, regardless
    # of whether two or eight series are drawn.
    n = len(series)
    figsize = (12.5, 6.5) if n > 4 else (10.5, 5.5)
    fig, ax = plt.subplots(figsize=figsize, dpi=120)
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
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1.0),
              framealpha=0.9, fontsize="small", borderaxespad=0)

    xticks = [1, 2, 10, 100, 1_000, 10_000, 100_000]
    xlabels = ["0%", "50%", "90%", "99%", "99.9%", "99.99%", "99.999%"]
    ax.set_xticks(xticks)
    ax.set_xticklabels(xlabels)

    fig.tight_layout(rect=(0, 0, 0.78 if n > 4 else 0.74, 1.0))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)
    print(f"[images] wrote {out_path.relative_to(REPO_ROOT)}")


def _series_with_fallback(real, synthetic_fn, mode: str):
    if real is not None:
        return real
    if mode != "real":
        return synthetic_fn()
    return None


def _suffix_for(series: list[PercentileSeries]) -> str:
    n_synth = sum(1 for s in series if s.synthetic)
    if n_synth == 0:
        return ""
    if n_synth == len(series):
        return "-synthetic"
    return "-mixed"


def _render(scenario: str, title: str, mode: str, synth_factory) -> int:
    """Render the four canonical SVGs for a scenario.

    ``synth_factory`` is a dict mapping the keys
    {ab, vegeta, wrk, hey, k6_bad, k6_good, jmeter_bad, jmeter_good} to
    a zero-arg callable returning a synthetic PercentileSeries used as
    a fallback when the corresponding measured file is absent.
    """
    results_dir = REPO_ROOT / "results" / scenario
    images_dir = REPO_ROOT / "images" / scenario

    if mode == "synthetic":
        loaded: dict[str, PercentileSeries | None] = {k: None for k in synth_factory}
    else:
        loaded = {
            "ab": parse_ab_csv(results_dir / "ab" / "percentiles.csv"),
            "vegeta": (
                parse_vegeta_hdr(results_dir / "vegeta" / "vegeta.hdr")
                or parse_wrk2_hdr(results_dir / "wrk2" / "wrk2.hdr")
                or parse_wrk2_txt(results_dir / "wrk2" / "wrk2.txt")
            ),
            "wrk": parse_wrk_text(results_dir / "wrk" / "wrk.txt", "wrk (closed loop)"),
            "hey": parse_hey_csv(results_dir / "hey" / "samples.csv", "hey (closed loop)"),
            "k6_bad": parse_k6_summary(
                results_dir / "k6-bad" / "summary.json",
                "k6 constant-vus (closed loop)",
            ),
            "k6_good": parse_k6_summary(
                results_dir / "k6-good" / "summary.json",
                "k6 constant-arrival-rate (open loop)",
            ),
            "jmeter_bad": parse_jmeter_csv(
                results_dir / "jmeter-bad" / "results.jtl",
                "JMeter ThreadGroup (closed loop)",
            ),
            "jmeter_good": parse_jmeter_csv(
                results_dir / "jmeter-good" / "results.jtl",
                "JMeter Precise Throughput Timer (open loop)",
            ),
        }

    for key, factory in synth_factory.items():
        loaded[key] = _series_with_fallback(loaded.get(key), factory, mode)

    missing = [k for k, v in loaded.items() if v is None]
    if missing:
        print(f"[images] {scenario}: missing series {missing}; run the scenario or use --mode synthetic",
              file=sys.stderr)
        return 1

    # 2-series (canonical, kept stable for the blog post).
    pair = [loaded["ab"], loaded["vegeta"]]
    plot_comparison(pair, images_dir / f"closed-vs-open-percentiles{_suffix_for(pair)}.svg",
                    f"{title} — ab vs Vegeta")

    # k6 worked example from the blog post.
    k6_pair = [loaded["k6_bad"], loaded["k6_good"]]
    plot_comparison(k6_pair, images_dir / f"k6-bad-vs-good{_suffix_for(k6_pair)}.svg",
                    f"{title} — k6 constant-vus vs constant-arrival-rate")

    # JMeter worked example (default ThreadGroup vs Precise Throughput Timer).
    jm_pair = [loaded["jmeter_bad"], loaded["jmeter_good"]]
    plot_comparison(jm_pair, images_dir / f"jmeter-bad-vs-good{_suffix_for(jm_pair)}.svg",
                    f"{title} — JMeter ThreadGroup vs Precise Throughput Timer")

    # All tools together: closed-loop tools first (warm reading order), then
    # open-loop tools — matplotlib's default cycle gives them distinct colours.
    all_series = [
        loaded["ab"], loaded["wrk"], loaded["hey"],
        loaded["k6_bad"], loaded["jmeter_bad"],
        loaded["vegeta"], loaded["k6_good"], loaded["jmeter_good"],
    ]
    plot_comparison(all_series, images_dir / f"all-tools{_suffix_for(all_series)}.svg",
                    f"{title} — eight load tools")

    # Timeline + throughput plots from per-request timestamps. Only run when
    # measured data is present — synthetic mode does not carry timestamps.
    if mode != "synthetic":
        _render_timeseries(scenario, title, results_dir, images_dir)
    return 0


# Tools picked for the latency-timeline scatter. All eight would render
# but the chart becomes hard to read past four overlapping clouds.
# These four cover both classes (closed/open) and both worked examples
# (k6, JMeter implicit through the comparison plot).
_TIMELINE_TOOLS: dict[str, tuple[str, str]] = {
    "ab (closed loop)":                          ("ab",         "timeseries.tsv"),
    "k6 constant-vus (closed loop)":             ("k6-bad",     "samples.csv"),
    "Vegeta (open loop)":                        ("vegeta",     "results.jsonl"),
    "k6 constant-arrival-rate (open loop)":      ("k6-good",    "samples.csv"),
}

_TIMELINE_PARSERS = {
    "timeseries.tsv":  parse_ab_timeseries,
    "samples.csv":     None,   # filled below: depends on tool dir name
    "results.jsonl":   parse_vegeta_timeseries,
    "results.jtl":     parse_jmeter_timeseries,
}


def _load_timeseries(label: str, results_dir: Path) -> Timeseries | None:
    tool_dir, filename = _TIMELINE_TOOLS[label]
    path = results_dir / tool_dir / filename
    if filename == "timeseries.tsv":
        return parse_ab_timeseries(path)
    if filename == "results.jsonl":
        return parse_vegeta_timeseries(path)
    if filename == "samples.csv":
        # k6-bad / k6-good both write CSV with the same schema; for hey the
        # schema differs but it isn't picked for the timeline subset.
        return parse_k6_timeseries(path)
    if filename == "results.jtl":
        return parse_jmeter_timeseries(path)
    return None


def _render_timeseries(scenario: str, title: str, results_dir: Path, images_dir: Path) -> None:
    measured: dict[str, Timeseries] = {}
    for label in _TIMELINE_TOOLS:
        ts = _load_timeseries(label, results_dir)
        if ts is not None:
            measured[label] = ts

    if not measured:
        return

    events = _events_for(scenario)
    plot_timeline(measured,
                  images_dir / "latency-timeline.svg",
                  f"{title} — latency vs. time",
                  events)
    plot_throughput(measured,
                    images_dir / "throughput-timeline.svg",
                    f"{title} — completed RPS vs. time (1 s bins)",
                    events)


def render_scenario_01(mode: str) -> int:
    healthy = lambda label, seed: (lambda: synthetic_healthy(label, seed=seed))
    return _render(
        "01-healthy",
        "Healthy server (control)",
        mode,
        synth_factory={
            "ab":          healthy("ab (closed loop)", 11),
            "wrk":         healthy("wrk (closed loop)", 12),
            "hey":         healthy("hey (closed loop)", 13),
            "k6_bad":      healthy("k6 constant-vus (closed loop)", 14),
            "jmeter_bad":  healthy("JMeter ThreadGroup (closed loop)", 15),
            "vegeta":      healthy("Vegeta (open loop, constant rate)", 16),
            "k6_good":     healthy("k6 constant-arrival-rate (open loop)", 17),
            "jmeter_good": healthy("JMeter Precise Throughput Timer (open loop)", 18),
        },
    )


def render_scenario_02(mode: str) -> int:
    closed = lambda label: (lambda: PercentileSeries(label, *_synth_closed_arrays(), synthetic=True))
    open_ = lambda label: (lambda: PercentileSeries(label, *_synth_open_arrays(), synthetic=True))
    return _render(
        "02-single-hiccup",
        "Single 1 s hiccup",
        mode,
        synth_factory={
            "ab":          synthetic_closed_loop,
            "wrk":         closed("wrk (closed loop)"),
            "hey":         closed("hey (closed loop)"),
            "k6_bad":      synthetic_closed_loop_k6,
            "jmeter_bad":  closed("JMeter ThreadGroup (closed loop)"),
            "vegeta":      synthetic_open_loop,
            "k6_good":     synthetic_open_loop_k6,
            "jmeter_good": open_("JMeter Precise Throughput Timer (open loop)"),
        },
    )


def _synth_closed_arrays() -> tuple[np.ndarray, np.ndarray]:
    s = synthetic_closed_loop()
    return s.percentiles, s.latencies_ms


def _synth_open_arrays() -> tuple[np.ndarray, np.ndarray]:
    s = synthetic_open_loop()
    return s.percentiles, s.latencies_ms


def _scenario_with_default_synth(scenario: str, title: str, mode: str) -> int:
    """Render an extended scenario using the closed/open synthetic shapes
    as fallback. Real measurements (when present) are what carry the
    pedagogy; the synthetic fallback only ensures the renderer is always
    exercisable.
    """
    closed = lambda label: (lambda: PercentileSeries(label, *_synth_closed_arrays(), synthetic=True))
    open_ = lambda label: (lambda: PercentileSeries(label, *_synth_open_arrays(), synthetic=True))
    return _render(
        scenario, title, mode,
        synth_factory={
            "ab":          closed("ab (closed loop)"),
            "wrk":         closed("wrk (closed loop)"),
            "hey":         closed("hey (closed loop)"),
            "k6_bad":      closed("k6 constant-vus (closed loop)"),
            "jmeter_bad":  closed("JMeter ThreadGroup (closed loop)"),
            "vegeta":      open_("Vegeta (open loop, constant rate)"),
            "k6_good":     open_("k6 constant-arrival-rate (open loop)"),
            "jmeter_good": open_("JMeter Precise Throughput Timer (open loop)"),
        },
    )


def render_scenario_03(mode: str) -> int:
    return _scenario_with_default_synth(
        "03-sustained-slowdown", "Sustained slowdown (10ms → 100ms baseline ramp)", mode)


def render_scenario_04(mode: str) -> int:
    return _scenario_with_default_synth(
        "04-gc-pauses", "Recurring GC pauses (200 ms every 10 s)", mode)


def render_scenario_05(mode: str) -> int:
    return _scenario_with_default_synth(
        "05-saturation", "Saturation (capacity 500 in-flight, target 1000 rps)", mode)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", default="02-single-hiccup",
                        help="scenario identifier (only 02-single-hiccup is supported in the MVP)")
    parser.add_argument("--mode", choices=["real", "synthetic", "auto"], default="auto",
                        help="real: only use measured data. synthetic: only use the canned distribution. "
                             "auto (default): use measured data when present, fall back to synthetic.")
    args = parser.parse_args()

    renderers = {
        "01-healthy": render_scenario_01,
        "02-single-hiccup": render_scenario_02,
        "03-sustained-slowdown": render_scenario_03,
        "04-gc-pauses": render_scenario_04,
        "05-saturation": render_scenario_05,
    }
    if args.scenario not in renderers:
        print(f"[images] scenario {args.scenario} not implemented yet", file=sys.stderr)
        return 2
    return renderers[args.scenario](args.mode)


if __name__ == "__main__":
    sys.exit(main())
