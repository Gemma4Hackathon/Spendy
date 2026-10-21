# Spendy on-device benchmark

Measurement procedure for the on-device (Cactus + Gemma 4 E2B INT4) path.
The instrumentation (`ios/Services/Perf/PerfMonitor.swift`) only reads clocks and
memory counters and prints `[PERF]` lines; it does not change app behavior.

## What gets logged

| Event | Meaning | Key fields |
|---|---|---|
| `model_load_end` | `cactusInit` (includes waiting for the serial inference queue) | `total_ms`, `peak_footprint_mb`, `min_available_mb` |
| `inference_end kind=text\|vision` | one `cactusComplete` call | `total_ms`, `ttft_ms`, `prefill_tps`, `decode_tps`, `prefill_tokens`, `decode_tokens`, `response_chars`, `thinking_chars` |
| `model_release` / `model_unload` | `cactusDestroy` | `ms`, `footprint_before_mb` |
| `health_scan_end` | whole scan, image picked to result | `total_ms`, `inferences`, `vision_inferences`, `model_loads`, `model_releases`, `metrics` |
| `insight_generation_end` | whole insight generation incl. retries | `total_ms`, `inferences` |
| `finance_summary_end` | whole finance summary | `total_ms`, `inferences` |

Every line also carries `footprint_mb` (process `phys_footprint`, what jetsam evaluates)
and `available_mb` (`os_proc_available_memory()`, headroom before jetsam).
Scopes report `peak_footprint_mb` / `min_available_mb` sampled every 100 ms.

Launch argument `-SpendyPerfVerbose` additionally prints `[PERF-RESULT]` lines with the
extracted metric names and values (off by default because real reports contain health data).

## Test inputs

Two photos of the same sample report (patient "TEST, PATIENT", not real data):
`IMG_9596` (photo of a screen, 3024x4032, glare/angle) and `IMG_9603` (flat scan, 1168x1650).
Ground truth, section 6 of the report:

| Test | Value | Flag |
|---|---|---|
| Glucose | 115 mg/dL | High |
| Hemoglobin A1c | 6.1 % | High |
| Total Cholesterol | 164 mg/dL | Normal |
| HDL Cholesterol | 81 mg/dL | Normal |
| Triglycerides | 45 mg/dL | Normal |
| LDL Cholesterol (Calculated) | 74 mg/dL | Normal |
| Non-HDL Cholesterol | 83 mg/dL | Normal |
| Cholesterol/HDL Ratio | 2.0 | Normal |

## Device and conditions

iPhone 12 Pro (6 GB RAM), iOS 27.0.1, Release build, battery above 50 %, Low Power Mode off,
phone at room temperature, no other apps in the foreground. Same conditions for baseline and
every later comparison.

## Parse a run

Copy the Xcode console to a text file, then:

```bash
python3 bench/parse_perf.py console.log
python3 bench/parse_perf.py console.log --csv run.csv
```
