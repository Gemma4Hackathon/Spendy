# Case study: making on-device Gemma 4 reliable on a 6 GB iPhone

Spendy is an iOS app that links spending habits to health-report results. Every AI feature runs
on the phone: Gemma 4 E2B (INT4, Cactus runtime) summarizes spending, reads a lab report from a
photo, and writes a combined health-and-spending action plan. This document records how the
on-device pipeline was taken from "demo that sometimes works" to "correct, deterministic and
measured", one evidence-backed change at a time. Raw numbers live in `bench/results/`.

## Summary

| Metric | Baseline | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|---|
| Text prompts silently dropped | 35 % | 0 % | 0 % | |
| Vision out-of-memory (`std::bad_alloc`) | 5/10 scans | 0/6 | 0/6 | |
| Model output that failed JSON parsing | not measured | frequent | 0/18 | |
| Lab values correct, flat scan (IMG_9603) | 2-3/8 | 0-2/8 | 2/8, then 7/8 after case 5 | |
| Lab values correct, photo of a screen (IMG_9596) | 1-2/8 | 1-2/8 | 8/8 | |
| Wrong values shown to the user | yes | yes (invented) | none | |
| Health-scan peak memory (limit 3,072 MB) | 2,065 MB | 1,774 MB | 1,779 MB | |
| Health scan, median | 140 s | 180 s | 269 s | |
| Insights | 171 s | 295 s | 192 s | |
| Finance summary | not meaningful (prompt dropped) | 53 s | 41 s | |
| Same input gives same output | no | partly | yes, token-for-token | |

Phase 2 traded scan latency for correctness on purpose; phase 3 targets latency.

## Setup and constraints

- Device: iPhone 12 Pro, 6 GB RAM, iOS 27. Measured per-app jetsam limit: **3,072 MB**
  (footprint + `os_proc_available_memory()` is constant across every sample).
- Model: Gemma 4 E2B with a LoRA fine-tune, converted to Cactus INT4 (4.7 GB). Weights are mmap'd
  read-only, so the resident footprint after load is only about 390 MB.
- No Core ML packages ship with these weights: vision, prefill and decode all run on the CPU.
  Decode is about 88 % of text-inference time, so **output length drives latency**.
- No `increased-memory-limit` entitlement (free signing team).

## Method

1. **Measure before changing anything.** A measurement-only `PerfMonitor` prints one
   `[PERF] event=... key=value` line per model load, inference (TTFT, prefill/decode tok/s, token
   counts, input hashes), model release and user flow, with peak footprint and minimum available
   memory sampled every 100 ms. `bench/parse_perf.py` turns a console log into tables.
2. **Fixed protocol.** Each round is a cold launch followed by the same four flows on the same
   inputs (Finance summary, two lab-report scans, Insights). Baseline is 5 rounds, each phase 3.
3. **Ground truth.** The sample lab report has 8 known values and flags; accuracy is scored
   against them, value and Normal/High status both.
4. **Diagnose with full evidence.** When something fails, log the complete model output first and
   classify the failure before touching a parser.
5. **Determinism as a tool.** After phase 2 every inference is greedy (temperature 0). The same input
   produces the same tokens in every round, so the effect of a change on one flow can be read
   directly from its token counts, and timing variance is isolated from content variance.

## Case 1: a third of prompts silently vanished

- **Symptom.** 35 % of text inferences prefilled only 9 tokens and answered
  "Please provide the text or image...". The Finance summary never received its full prompt.
- **Hypothesis.** The prompt was being lost before it reached the model, not ignored by it.
- **Evidence.** Requests with the same content but a different serialized hash behaved differently;
  identical hashes always behaved the same. Cactus's `parse_messages_json` (C++) looks for
  `"content"` only *after* `"role"`. Swift dictionaries serialized with `JSONSerialization` have no
  stable key order, so whenever `content` was written first it was skipped.
- **Fix.** Serialize messages with a fixed key order (`orderedMessagesJSON`).
- **Result.** Dropped prompts 35 % to **0 %**; Finance received its full 594-token prompt in 3/3 rounds;
  identical inputs became reproducible.
- **Lesson.** An interface bug looked like a model-quality problem. Hashing inputs made it visible.

## Case 2: the vision path ran out of memory

- **Symptom.** Half of the scans crashed inside vision inference with `std::bad_alloc` at
  2.05-2.21 GB footprint.
- **Evidence.** Resizing the photo in Spendy changed nothing. Reading Cactus showed why: every image
  is resized to `vision_default_output_length x 9` patches regardless of input size
  (2,520 patches at the default budget of 280 tokens).
- **Fix.** Lower the visual token budget to 140 (Gemma 4 supports 70/140/280/560/1120).
- **Result.** `bad_alloc` 5/10 to **0/6**; scan peak 2,065 to 1,774 MB median (-14 %); minimum
  headroom 866 to 1,276 MB.
- **Trade-off.** Fewer pixels per image. Case 4 shows that this was not where accuracy was lost:
  the vision path was already inventing values at 280.

## Case 3: model JSON that would not parse

- **Symptom.** Once prompts arrived intact, many long structured outputs failed JSON parsing,
  triggering repair inferences, model reloads and retries (one scan took 463 s, one Insights 431 s).
- **Diagnosis first.** I changed logging to print the full failing response, then classified all
  four failures in one run: none were truncated or wrapped in markdown. All were structural:
  an array closed with `}`, a string missing its closing quote, a missing final brace, and a
  corrupted key separator (`"normalRange} < 200"`).
- **Root cause (inferred, then supported by data).** Cactus defaults `repetition_penalty` to 1.1 and
  subtracts `log(1.1)` once per occurrence of every token in the last 128 sampled tokens. In long
  JSON the structural tokens (`":"`, `","`, quotes) repeat constantly, so they are progressively
  penalized until the model emits a different, wrong delimiter.
- **Fix.** Repetition penalty off and greedy decoding for every structured task, plus a small
  tolerant parser (`LenientJSON`) that only touches brackets, quotes and trailing commas, never
  values. Template echo (`REPLACE` placeholders) is treated as a failed answer.
- **Result.** Parse failures to **0/18** inferences over 3 rounds, and the tolerant parser never had
  to repair anything: the outputs were valid as generated. Insights 295 to **192 s** with a single
  inference; zero model reloads.

## Case 4: the vision model invents lab values

- **Symptom.** With JSON fixed, the vision path returned well-formed results that were mostly wrong:
  1-2 of 8 values correct, plus tests that are not on the report (BUN, Creatinine).
- **Evidence from the outputs.** The values it got right (Glucose 115, HbA1c 6.1) are the two printed
  in large type in the report's summary box. Most other "values" are textbook clinical thresholds
  (total cholesterol 200, triglycerides 150, HbA1c 5.7) or fragments placed on the wrong row
  (Hemoglobin 115 with the cholesterol range 125-200).
- **Root-cause hypothesis: input resolution.** Cactus scales every image to about
  `budget x 9 x 16^2` pixels: at 140 tokens the flat scan becomes 432x672 px and the screen photo
  624x480 px. Table text ends up about 6 px tall, and one visual token covers a 48x48 px area
  (about 4 lines x 8 characters). The model sees layout and large type, and fills the rest from
  its language prior. Raising the budget is not an option: at 280 the vision pass already ran out
  of memory half the time.
- **Confirmation experiment.** _Pending: the same report cropped to the results table (text about
  2.5x larger at the same 140-token budget). If vision accuracy rises sharply, resolution is
  confirmed as the root cause._
- **Fix.** Never show an unverified vision value. Apple Vision OCR reads the same image (with the
  model kept loaded) and a vision value is kept only if OCR read it on the metric's own table row.
  Missing values come from Gemma 4 structuring the OCR text. Normal/High status is decided in
  Swift from the report's own Flag column, then its printed reference range, then a standard range
  table; the model's opinion is the last resort.
- **Result.** IMG_9596 1-2/8 to **8/8** (values and flags) in all 3 rounds; no wrong value displayed.

## Case 5: the text model skipped the results table

- **Symptom.** On the flat scan the deterministic text model returned only the four metrics in the
  summary box; the whole lipid panel was missing (2/8), identically in all 3 rounds.
- **Evidence.** OCR had read every table row correctly; the output was not truncated.
- **Fix.** Read known metrics directly from OCR table rows (label line plus a same-row line that
  starts with a reading; reference-range lines skipped; plausibility range per metric) and use
  them only to fill keys the model left out. No extra inference.
- **Result.** IMG_9603 2/8 to **7/8**, confirmed on device. The eighth value (ratio 2.0) is
  intentionally dropped because OCR read it as "20", which fails the plausibility check:
  **a missing value is better than a wrong one in a health app.**

## Case 6: latency (phase 3)

_In progress. Plan: run OCR first and use vision only as a fallback (vision cost 96-170 s per
scan and contributed no displayed value), and stop asking the model for fields that Swift already
computes or the UI never shows (health status, ranges and evidence; Insights scores; Finance
amounts)._

## Lessons

- Instrument first; the cheapest fix is the one you do not have to guess.
- Many "model quality" problems were interface or sampling problems: key order, a default
  repetition penalty, a fixed pixel budget.
- Keep the model on the part it is good at (structuring and writing) and keep facts that can be
  checked deterministically (values, flags, totals) in code.
- Greedy decoding made the benchmark reproducible and every regression debuggable from one run.
