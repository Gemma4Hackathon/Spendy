# Case study: making on-device Gemma 4 reliable on a 6 GB iPhone

Spendy is an iOS app that links spending habits to health-report results. Every AI feature runs
on the phone: Gemma 4 E2B (INT4, Cactus runtime) summarizes spending, reads a lab report from a
photo, and writes a combined health-and-spending action plan. This document records how the
on-device pipeline was taken from "demo that sometimes works" to "correct, deterministic and
measured", one evidence-backed change at a time. Raw numbers live in `bench/results/`.

## Summary

| Metric | Baseline | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---|---|---|---|---|---|
| Text prompts silently dropped | 35 % | 0 % | 0 % | 0 % | 0 % |
| Vision out-of-memory (`std::bad_alloc`) | 5/10 scans | 0/6 | 0/6 | 0 (vision not needed) | 0 (vision not needed) |
| Model output that failed JSON parsing | not measured | frequent | 0/18 | 0/12 | 0/12 |
| Lab values correct, flat scan (IMG_9603)* | 2-3/8 | 0-2/8 | 2/8, then 7/8 after case 5 | 8/8 | 8/8 |
| Lab values correct, photo of a screen (IMG_9596) | 1-2/8 | 1-2/8 | 8/8 | 8/8 | 8/8 |
| Wrong values shown to the user | yes | yes (invented) | none | none | none |
| Model advice checked before display | no | no | no | no | every sentence |
| Health-scan peak memory (limit 3,072 MB) | 2,065 MB | 1,774 MB | 1,779 MB | 786 MB | 763 MB |
| Health scan, median | 140 s | 180 s | 269 s | 22 s | **12 s** |
| Insights | 171 s | 295 s | 192 s | 84 s | **26 s** |
| Finance summary | not meaningful (prompt dropped) | 53 s | 41 s | 21 s | 25 s |
| Same input gives same output | no | partly | yes, token-for-token | yes | yes, and the Mac matches the iPhone |

Phase 2 traded scan latency for correctness on purpose; phase 3 took it back (12x faster scans)
without giving up accuracy; phase 4 made the model's advice checkable and cut Insights from 84 s to
26 s. *Phase 3 and 4 scanned a different export of IMG_9603 (165 vs 160 OCR lines); IMG_9596 is the
identical-input comparison: 147 s baseline, 310 s phase 2, 22.5 s phase 3, 12.4 s phase 4.

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
- **Confirmation experiment.** Same build, same prompt, same 140-token budget; the only change was
  cropping the photo to the results table, which makes the text about 2.5x larger after Cactus's
  resize. OCR-verified vision values went from **1-2/8 to 7/8**, all with the correct flag. The
  eighth (the ratio) could not be confirmed because OCR itself reads "2.0" as "20". The model can
  read the report; the fixed pixel budget was hiding the digits. Root cause confirmed.
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

- **Symptom.** Correct but slow: scans 213-325 s, Insights 192 s. Latency is decode-bound
  (about 4-7 tok/s on CPU), and two things were spending most of the tokens.
- **Evidence.** (1) Vision cost 96-170 s per scan and contributed no displayed value (case 4).
  (2) Much of every output was fields Swift already decides or the UI never shows: health status,
  ranges and evidence text (decided by the verifier); Insights risk score and amount at risk
  (computed in Swift, then copied back by the model); icons, colors, timeframes.
- **Fix.** OCR first; vision only as a fallback when OCR finds fewer than 2 metrics, and even then
  only OCR-confirmed values are shown. The model is asked only for what needs language: health
  `name/value/unit`; Insights advice sentences; Finance summary sentences. Every number the user
  sees (amounts, caps, scores, lab values and flags) is computed in Swift.
- **Result.** Scan 269 s to **22 s** (identical-input image: 310 s to 22.5 s), Insights 192 s to
  **84 s**, Finance 41 s to **21 s**, scan peak memory 1.78 GB to **0.79 GB**, accuracy 8/8 on both
  images, 0 parse failures, deterministic across rounds.
- **Bugs the device runs caught before the benchmark.** A landscape photo returned four invented lab
  values through the "OCR failed, show vision unverified" path, so that path was removed: nothing
  unverified is ever displayed. The table reader turned the HbA1c unit "% of total Hgb" into a
  phantom "Hemoglobin 115". The model computed a weekly cap of NT$765 for an NT$800 month, which
  is why arithmetic moved to Swift. Each fix was regression-tested by replaying every logged
  iPhone scan through the verifier on the Mac (`bench/replay`).
- **Thermal.** The phone reached `serious` by the last flow in every round; decode speed varies
  with context length and temperature (6.3 to 10 tok/s), which is now logged per inference.

## Case 7: data minimization and checking the model's advice (phase 4)

- **Symptom.** Scans were prefill-bound (TTFT 13-17 s of 20-24 s), and the model's advice still had
  wrong numbers that prompt rules kept chasing: a NT$765/week cap for an NT$800 month, a month of
  spending called a 7-day saving, categories cut to zero, lab values promised to improve in 7 days.
- **Fix, input side.** Gemma 4 gets only the OCR lines Swift has not read: verified table rows, flag
  and reference-range columns, patient and specimen rows, duplicates and long prose are left out
  (165 to 68 lines). Patient details never reach the model.
- **Fix, output side.** Every sentence the model writes is checked before display
  (`OutputGuardrail`): each NT$ amount must be one Swift computed, a monthly total next to "per week"
  is a unit error, "to zero" is rejected, outcomes may not promise lab changes, and causal claims
  must be hedged. A failing field is replaced by Swift-written text and counted in the log.
- **What the device runs caught next.** Two errors passed the first version, and each became a rule
  with a failing test first: (1) the screen photo produced "Diabetes Risk 7 %" shown as Normal; the
  value is on the report, but the report rates it "Slightly Increased" on a graphic scale, so risk
  estimates are no longer shown as lab results. (2) Finance wrote "Limit Late Night spending to
  NT$210 per week"; NT$210 is the Food Delivery cap (Late Night runs about NT$77 a week), so an
  amount must now belong to the category the sentence names. Replaying all 276 logged model
  sentences (`bench/guardrail_replay`): 48 flagged, every one actually wrong.
- **Result.** OCR-text prefill 1,220 to 640 tokens; scans 22 s to **12 s**; 8/8 on both images; the
  guardrail replaces the one wrong Finance sentence every round. 37 unit tests on real device OCR and
  model outputs run with `swift test`; each new rule was mutation-checked.

## Case 8: an Insights regression, and a Mac that answers like the iPhone (phase 4)

- **Symptom.** With case 7 in place, Insights slowed from 84 s to **122 s**. Measuring every phase
  is what caught it: a correctness fix (weekly targets for every diet category in the prompt) had
  made the prompt longer, and the model then restated the amount and the health sentence in every
  action description (121 to 505 characters; 578 output tokens).
- **Evidence.** Decode speed on this CPU path falls with context length: OCR text decoded at
  6.4-6.9 tok/s with about 1,220 tokens of context and 9.2-9.5 with about 640; Insights ran at
  5.1-5.9 tok/s. A longer prompt makes every output token slower, not just prefill.
- **Fix.** Split the work by what each side is good at. The model writes only what needs wording:
  the movement and food plan and one sentence per finding on why a habit may affect a metric.
  Swift writes cause details, weekly caps, actions and 7-day outcomes from fixed templates, which a
  test checks against the guardrail for every category at NT$10-5,000. The diet reasons per metric
  come from Swift too, after a draft gave "high sodium" as a reason for HbA1c.
- **Testing prompts without the phone.** Cactus builds for macOS. The Mac harness
  (`bench/mac_insights`) rebuilds the exact device messages from a log (same `messages_hash`) and
  produced a byte-identical answer to the iPhone's, so prompt drafts could be judged on the Mac.
  Drafts there caught a risk sentence about the wrong category and a plan promising better
  glucose; both are now replaced by the composer and covered by tests that use those real answers.
- **Result.** Insights **122 s to 26 s** (prefill 1,138 to 592 tokens, decode 578 to 182, decode
  5.3 to 9.1 tok/s), 0 fields replaced, identical output in every round. The device run matched the
  Mac's prediction exactly (hash, token counts and the 640-character answer).
- **Trade-off.** Actions are now templates, so they vary less between users. In a health app,
  correct and predictable beat varied.

Also in phase 4: Insights shows real progress from the streamed JSON (finished sections, current
step, elapsed seconds) instead of a spinner; the scan screen shows the real pipeline steps and a
specific error; a photo with no digits is rejected in 0.3 s instead of running vision for 19 s.

## What I would do next

- **OCR-guided crop for vision.** Case 4 shows vision reads a cropped table correctly at the same
  memory cost. OCR bounding boxes already locate the results table, so the vision fallback could
  be fed that crop instead of the whole page.
- **Apply the case 8 split to Finance.** Its checklist is the one field the guardrail still replaces
  every round; generating it in Swift would also save output tokens.
- **Run the Mac harness on every prompt change**, comparing output and token counts with the last
  device run before anyone picks up the phone.

## Lessons

- Instrument first; the cheapest fix is the one you do not have to guess.
- Many "model quality" problems were interface or sampling problems: key order, a default
  repetition penalty, a fixed pixel budget.
- Keep the model on the part it is good at (structuring and writing) and keep facts that can be
  checked deterministically (values, flags, totals, caps) in code.
- Greedy decoding made the benchmark reproducible and every regression debuggable from one run.
- Measure every phase, including after correctness fixes: case 8's regression came from one.
- Prove a proxy before trusting it: byte-identical output is what made the Mac a valid test bench.
