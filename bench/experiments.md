# Optimization experiments

Each phase is measured with the protocol in `bench/README.md` (3 rounds per phase) and compared
against `bench/results/baseline-2026-10-21.md` (5 rounds).

## Phase 1: prompt loss + vision memory

| Change | Where | Reason |
|---|---|---|
| Serialize chat messages with fixed key order `role`, `content`, `images` | `ios/Services/CactusManager.swift` (`orderedMessagesJSON`) | Cactus's `parse_messages_json` only finds `content` after `role`; unstable `JSONSerialization` key order dropped prompt content in 35 % of baseline text inferences |
| Visual token budget 280 to 140 (`vision_default_output_length`) | `cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt` (not in git) | Cactus resizes every image to `vision_default_output_length x 9` patches (2,520 at 280). Halving the budget halves the patches; vision `std::bad_alloc` hit 5/10 baseline scans at 2.05-2.21 GB footprint. Gemma 4 supports budgets 70/140/280/560/1120 |

Reproduce the config change after converting weights:

```bash
sed -i '' 's/^vision_default_output_length=280$/vision_default_output_length=140/' \
  ~/Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
```

Revert by setting the value back to 280. Then Product > Clean Build Folder in Xcode so the app bundles the new config.
The `app_launch` record prints `vision_tokens=<value>` from the bundled config.txt to confirm which budget ran.

Expected trade-off: fewer visual tokens may lower extraction accuracy on a dense table (Google recommends higher budgets for small or dense detail). If accuracy drops, fall back to plan B (OCR first, vision only as fallback).

## Phase 2: JSON reliability and verified health extraction

Diagnosis: `bench/results/phase2-diag-2026-10-21.md`. Measured on the same protocol, 3 rounds.

| Change | Where | Reason |
|---|---|---|
| `repetition_penalty` 1.0 (off) for text and vision; temperature 0 (greedy) for every JSON task | `CactusManager.swift`, providers | Cactus defaults the penalty to 1.1 and subtracts `log(1.1)` once per occurrence of each of the last 128 sampled tokens (`cactus/engine/engine_model.cpp`). In long JSON the repeated `":"`/`","`/quote tokens are pushed down until the model writes `}` or `>` instead. Root cause is inferred from code + outputs; the phase 2 runs test it |
| Shared tolerant JSON parser: swaps mismatched closers, closes strings cut by a newline (or escapes the newline inside prose), appends missing closers, drops trailing commas | `LenientJSON.swift`, all three providers | 3 of 4 diag failures parse after repair. Each repair logs `event=json_repair` |
| Health scan: Gemma 4 vision first, then Apple Vision OCR without releasing the model; a vision value is kept only if OCR read it on the same table row as the metric name; under 5 confirmed, Gemma 4 structures the OCR text and results are merged | `OnDeviceHealthReportExtractor.swift`, `HealthReportVerifier.swift` | Vision invented 7/8 values on IMG_9596. Removes the JSON-repair inference (147 s, itself unparseable) and the model release + reload (race: a scan or Insights started during the background reload got "model not loaded") |
| Status in Swift: report Flag column on the row, then printed reference range on the row, then a standard range table, model status last; evidence trace generated from the final metrics | `HealthReportVerifier.swift` | Model reported A1c 6.1 vs <5.7 as Normal and shifted the range column by one row |
| Insights and Finance: template echo (`REPLACE`, schema instructions) treated as a failed answer; numbers accepted where strings are expected | providers | greedy decoding can copy the template |
| `loadModel` retries after `.failed` | `CactusManager.swift`, `AppEnvironment.swift` | a failed load could never be retried |

Offline check before the device run (macOS Vision OCR on `IMG_9596.HEIC` / `IMG_9603.heic`, model outputs from the diag log):
vision output keeps 1/8 (Glucose, correct) on both images; OCR-text output keeps 8/8 with values, status and range matching the ground truth on both.
macOS and iOS OCR can differ, so the device run is the real check.

Device result (3 rounds, `bench/results/phase2-2026-10-21.md`): 0 parse failures, 0 reloads, Insights 1 inference;
IMG_9596 8/8, IMG_9603 2/8 because the text model returned only the Key Findings block on the flat scan.

| Change after the benchmark | Where | Reason |
|---|---|---|
| Known metrics read from OCR table rows (label line + same-row reading, plausibility range, verified on its row) fill keys the models left out | `HealthReportVerifier.tableCandidates`, extractor (`bd0c74a`) | IMG_9603 lipid panel missing. Offline on iPhone OCR from r1-r3: IMG_9603 7/8, IMG_9596 8/8. Confirmed on device for IMG_9603 (7/8, `table_filled=5`) |
