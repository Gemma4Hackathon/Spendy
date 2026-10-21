#!/usr/bin/env python3
"""Summarize [PERF] lines from a Spendy Xcode console log.

Usage:
    python3 bench/parse_perf.py console.log            # summary table
    python3 bench/parse_perf.py console.log --csv out.csv

Every "[PERF] event=... key=value ..." line becomes one row. The summary groups
rows by event (inference rows are further split by kind=text|vision) and prints
count / median / min / max for the numeric fields that matter.
"""
import argparse, csv, re, statistics, sys
from collections import defaultdict

LINE = re.compile(r"\[PERF\] (.*)$")
PAIR = re.compile(r'(\w+)=("[^"]*"|\S+)')
FIELDS = ["total_ms", "ms", "ttft_ms", "cactus_total_ms", "prefill_tps", "decode_tps",
          "prefill_tokens", "decode_tokens", "inferences", "vision_inferences",
          "model_loads", "model_releases", "peak_footprint_mb", "min_available_mb",
          "footprint_mb", "available_mb", "metrics"]

def parse(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if not m:
                continue
            row = {k: v.strip('"') for k, v in PAIR.findall(m.group(1))}
            if "event" in row:
                rows.append(row)
    return rows

def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--csv")
    a = ap.parse_args()
    rows = parse(a.log)
    if not rows:
        sys.exit("no [PERF] lines found")
    if a.csv:
        keys = sorted({k for r in rows for k in r})
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {len(rows)} rows to {a.csv}")
    groups = defaultdict(list)
    for r in rows:
        ev = r["event"]
        if not ev.endswith("_end") and ev not in ("model_release", "model_unload"):
            continue
        key = ev + (f"[{r['kind']}]" if "kind" in r else "")
        groups[key].append(r)
    for key in sorted(groups):
        g = groups[key]
        ok = [r for r in g if r.get("result", "ok") == "ok"]
        print(f"\n== {key}  n={len(g)} ok={len(ok)}")
        for fld in FIELDS:
            vals = [num(r.get(fld)) for r in ok]
            vals = [v for v in vals if v is not None]
            if vals:
                print(f"  {fld:<18} median={statistics.median(vals):>10.1f}  min={min(vals):>10.1f}  max={max(vals):>10.1f}")
        truncated = sum(1 for r in ok if r.get("hit_max_tokens") == "true")
        if truncated:
            print(f"  hit_max_tokens     {truncated}/{len(ok)}")
    failures = defaultdict(int)
    for r in rows:
        if r["event"] == "parse_failure":
            failures[(r.get("source", "?"), r.get("reason", "?"))] += 1
    if failures:
        print("\n== parse_failure")
        for (source, reason), n in sorted(failures.items()):
            print(f"  {source:<22} {reason:<18} {n}")

if __name__ == "__main__":
    main()
