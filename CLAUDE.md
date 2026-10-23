# CLAUDE.md: Spendy on-device optimization

Handoff notes for continuing the Spendy optimization work in Claude Code. Read this first, then
`bench/README.md`, `bench/experiments.md`, `bench/results/baseline-2026-10-21.md`,
`bench/results/phase1-2026-10-21.md` and `bench/results/phase2-2026-10-21.md`. The full story is
`docs/case-study.md`; the latest numbers are `bench/results/phase4-2026-10-22.md`.

## Working rules (from John)

- Reply in Traditional Chinese, keep technical terms in English. Concise, no filler.
- Do not guess. Say "I'm not sure" or verify first. Mark any inference as speculation.
- Before each step, say what you are about to do, then do it. Confirm direction before larger changes.
- Show the diff for every code change; commit only after the build succeeds.
- John operates the iPhone. You cannot tap the UI; you build, install and analyse logs.

## Layout

```
~/Gemma4Good/
├── Spendy/        this repo (origin = Gemma4Hackathon/Spendy, fork = LarryinMexico/Spendy)
├── cactus/        cactus-compute/cactus @ d917981f + restore/cactus-d917981f.patch (shallow clone)
│   ├── apple/cactus-ios.xcframework        copied from restore/
│   ├── weights/gemma-4-e2b-m23k-cot-sft-lora-int4/   INT4 model, 4.7 GB, not in git
│   └── venv/      Python 3.12, packages pinned by cactus/requirements-may2026.txt
└── bench-logs/    raw console logs (NOT in git; contain model output about spending data)
```

`ios/Spendy.xcodeproj` references `../../cactus/...`, so Spendy and cactus must stay siblings.

## Do not commit

- `ios/Spendy.xcodeproj/project.pbxproj`: has unrelated Xcode auto-edits ("Recovered References"). Leave it unstaged.
- `ios/Spendy.xcodeproj/xcshareddata/`: John's local shared scheme (Run = Release, launch arg `SpendyPerfVerbose`).
- Anything from `~/Gemma4Good/bench-logs/`.

Commit author: `SamChen <sam92.chen@gmail.com>`.

## Environment

- Mac: macOS 27.0.1, Xcode 27.1 (iphoneos27.1 SDK), 16 GB RAM.
- Device: iPhone 12 Pro (iPhone13,3), 6 GB RAM, iOS 27.0.1, signed with John's Personal Team (7-day expiry).
- Model conversion needs the pinned venv (`requirements-may2026.txt`). Latest transformers produced weights the
  bundled framework rejects ("Matrix dimensions incompatible"). Conversion needs RAM headroom; close other apps.
- Weights `config.txt` currently has `vision_default_output_length=140` (original 280). Not in git; see
  `bench/experiments.md`. After changing anything in the weights folder, Product > Clean Build Folder.

## Instrumentation (measurement only)

`ios/Services/Perf/PerfMonitor.swift` prints one-line `[PERF] event=... key=value` records: model load,
each inference (TTFT, prefill/decode tps, token counts, input hashes), model release, and whole flows
(`finance_summary`, `health_scan`, `insight_generation`) with inference/reload counts, `peak_footprint_mb`
and `min_available_mb` sampled every 100 ms. First record is `app_launch config=... verbose=... vision_tokens=...`.
With launch arg containing `SpendyPerfVerbose`, `[PERF-RESULT]` lines show extracted metrics and a
240-char response preview (double quotes are replaced by single quotes in that preview).
`bench/parse_perf.py <log>` summarizes a log.

## Benchmark protocol

Per round: Xcode console cleared, cold launch (stop then run), wait for `Model ready`, then Finance summary
(Fin Assistant tab, refresh), Health Scan IMG_9603 (flat scan), Health Scan IMG_9596 (photo of a screen),
Insights (Generate / Regenerate). John saves the console with `pbpaste > ~/Gemma4Good/bench-logs/<name>.log`.
Do not add or edit spending entries between rounds (Finance input must stay identical).
Baseline = 5 rounds, each phase = 3 rounds. Ground truth for the sample report is in `bench/README.md`.

## Key findings so far

- Per-app jetsam limit on this device: 3,072 MB (footprint + `os_proc_available_memory()` is constant).
- Weights are mmap'd read-only (`cactus/graph/graph_io.cpp`); footprint after load is about 390 MB.
- Decode is about 88 % of text-inference time (5.5 tok/s median); output length drives latency.
- Root cause of dropped prompts (fixed in phase 1): Cactus `parse_messages_json` (`cactus/ffi/cactus_utils.h`)
  only finds `"content"` after `"role"`; Swift dictionary + `JSONSerialization` key order was unstable.
  Fixed by `orderedMessagesJSON` in `CactusManager.swift`.
- Cactus resizes every image to `vision_default_output_length x 9` patches regardless of input size
  (`cactus/models/gemma4/model_gemma4_vision.cpp`), so resizing in Spendy does not change vision memory.
- No Core ML packages ship with the INT4 weights: vision, audio and prefill all run on CPU.
- No `increased-memory-limit` entitlement.

## Status

- Baseline: done (`bench/results/baseline-2026-10-21.md`).
- Phase 1 (prompt-order fix + visual tokens 140): done (`bench/results/phase1-2026-10-21.md`).
  Prompt loss 35 % to 0 %, vision bad_alloc 5/10 to 0/6, scan peak 2,065 to 1,774 MB median.
- Phase 2 (repetition_penalty off + temperature 0, `LenientJSON`, OCR-verified health scan, status in Swift):
  done (`bench/results/phase2-2026-10-21.md`, commit `29208e0`). 0 JSON failures, 0 reloads, Insights 1 inference,
  fully deterministic. IMG_9596 8/8; IMG_9603 2/8 (text model skipped the lipid panel). Scans 213-325 s,
  Insights 192 s, Finance 41 s. Vision still invents values and contributes nothing to the final result.
- After the benchmark: `bd0c74a` fills metrics from OCR table rows. Confirmed on device: IMG_9603 7/8.
- Phase 3 (OCR first, vision fallback only, shorter outputs, all numbers in Swift): done
  (`bench/results/phase3-2026-10-22.md`, commit `d8b9d67`). Scan 22 s, Insights 84 s, Finance 21 s, scan peak
  786 MB, 8/8 on both images, 0 parse failures. Phase 3 used a different export of IMG_9603 (425,910 bytes);
  IMG_9596 is the identical-input comparison.
- Vision root cause (confirmed): Cactus's fixed pixel budget leaves table text about 6 px tall; a cropped table
  reads 7/8 at the same budget. Story for interviews: `docs/case-study.md`.
- Phase 4 (OCR prompt minimization, output guardrail, streaming progress, UI fixes, Insights split): done
  (`bench/results/phase4-2026-10-22.md`, commit `41a26bf`). Scan 12 s, Insights 26 s, Finance 25 s, scan peak
  763 MB, 8/8 on both images, 0 parse failures, Insights output identical every round.

## Checks before a device run

- `swift test` at the repo root (pure logic in `Package.swift`; runs outside the sandbox).
- `bench/replay`: verifier changes against every logged device scan.
- `bench/guardrail_replay`: guardrail rules against every logged Finance/Insights sentence.
- `bench/mac_insights`: rebuilds the device Insights prompt from a log and runs it with Cactus on the Mac;
  greedy output is byte-identical to the iPhone. `libcactus.dylib` is built outside the cactus repo
  (commands in `run.py`). Check `messages_hash` against the device log before trusting a run.

## Next

- Optional: move the Finance checklist to Swift (the guardrail replaces one item every round).
- Optional: OCR-guided crop for the vision fallback (`docs/case-study.md`, What I would do next).
