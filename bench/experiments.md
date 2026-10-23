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

### Vision root-cause experiment (2026-10-21, `phase3-vision-crop.log`, phase 2 build)

IMG_9603 cropped to the section 6 table, same prompt and `vision_tokens=140`: OCR-verified vision
values 7/8 with correct flags (full page: 1-2/8). The ratio row was not confirmable because OCR
reads "2.0" as "20". Vision decode 751 tokens, 114 s, peak 1,725 MB. Conclusion: vision errors on the
full page come from Cactus's fixed pixel budget (`model_gemma4_vision.cpp`: about
`budget x 9 x 16^2` px, 432x672 for this page, table text about 6 px tall), not from the model's
ability to read the table.

## Phase 3: OCR-first scan and shorter outputs

Results: `bench/results/phase3-2026-10-22.md`.

| Change | Where | Reason |
|---|---|---|
| OCR first; Gemma 4 vision only when OCR finds fewer than 2 metrics, values shown only if OCR confirms them on their row; no text or OCR failure rejects the image | `OnDeviceHealthReportExtractor.swift` | Vision cost 96-170 s per scan with no displayed value; a landscape photo produced invented values through the unverified path |
| Health prompts ask for `name/value/unit` only | same | status, range and evidence are decided in `HealthReportVerifier` |
| Insights: scores, amounts, icons, colors, causes, health details, targets and timeframes filled in Swift; findings paired with diet-related categories first; outcomes must be 7-day behavior results, not lab changes | `OnDeviceInsightGenerator.swift` | fewer output tokens; the model promised lab changes in 7 days and linked Entertainment to HbA1c |
| Finance: items, amounts, weekly caps and table computed in Swift; model writes summary sentences | `OnDeviceFinanceSummaryProvider.swift` | the model miscalculated caps (NT$765/week for NT$800/month) |
| Plausibility ranges on every verified value; value lines are never metric names; "total ... Hgb" is not hemoglobin | `HealthReportVerifier.swift` | ratio "20" (OCR misread) and a phantom "Hemoglobin 115" from the HbA1c unit |
| `LenientJSON` drops a key without a value | `LenientJSON.swift` | `"unit":"%",""}` |
| `thermal_state` per inference; full parsed outputs in verbose logs; `bench/replay` | `PerfMonitor.swift`, `bench/` | explain decode variance; review output quality; regression-test the verifier on logged device scans |

## Phase 4: data minimization, guardrails, streaming, tests

Results: `bench/results/phase4-2026-10-22.md` (`phase4-r1..r3` before the Insights split, `phase4-final-r1..r3` after).

| Change | Where | Reason |
|---|---|---|
| SwiftPM package over the pure logic; `swift test` on the Mac (37 tests, fixtures from device OCR and model answers) | `Package.swift`, `Tests/SpendyCoreTests` | verification lived in scratch scripts; no regression net |
| OCR prompt keeps only lines Swift has not read: no verified table rows, flags, ranges, patient/specimen rows, duplicates or prose | `OCRPromptBuilder.swift`, extractor | prefill-bound scans; patient details do not need to reach the model. 165 to 68 lines, prefill 1,220 to 640 tokens |
| Output guardrail on every model sentence (amount must be Swift-computed and belong to the named category, monthly-as-weekly, zero targets, lab promises, unhedged causal claims); failing fields replaced by Swift text, `event=guardrail` logged | `OutputGuardrail.swift`, Finance and Insights | prompt rules alone kept missing wrong numbers; `wrong_category` added after "Late Night NT$210/week" (Food Delivery's cap) |
| Risk estimates ("8-Year Diabetes Risk 7%") not shown as lab results | `HealthReportVerifier.swift` | rated on a graphic scale the app cannot read; shown as Normal, report says Slightly Increased |
| Vision fallback skipped when OCR text has no digits | extractor | a landscape photo ran vision for 19 s (1,474 MB peak) with nothing to confirm against |
| Insights progress from streamed partial JSON; real scan stages and specific errors | `InsightProgress.swift`, `HealthReportExtracting.swift`, views | 80-120 s behind a spinner; generic error text |
| Insights split: model writes plan and risk sentences only; Swift writes causes, caps, actions, outcomes; risk reasons per metric from Swift; `maxTokens` 1000 to 400 | `InsightComposer.swift` | Insights regressed to 122 s (578 output tokens restating amounts); 1,138 / 578 to 592 / 182 tokens, 26 s |
| Mac harness: device messages rebuilt from a log (hash-checked) and run with Cactus built for macOS | `bench/mac_insights` | byte-identical to the iPhone for greedy decoding; prompt drafts checked without the phone |
| Guardrail replay over logged answers | `bench/guardrail_replay` | new rules checked for false positives on 276 real sentences |
