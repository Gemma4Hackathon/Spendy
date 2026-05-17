# Spendy

Spendy is an iOS SwiftUI app for private, on-device health-aware spending analysis. It connects everyday spending behavior with health markers from a lab report, then uses Gemma 4 E2B running locally through Cactus to generate practical financial and health behavior guidance.

This project was built for the Gemma 4 Good Hackathon. It targets the Health & Sciences impact area and the Cactus mobile/wearable technology track.

## Why This Matters

Personal finance apps usually optimize for budgets. Health apps usually explain biomarkers. Spendy connects the two:

- Spending patterns: food delivery, fast food, sugary drinks, coffee, late-night purchases, entertainment, groceries.
- Health markers: glucose, HbA1c, cholesterol, BMI, blood pressure, hemoglobin, triglycerides.
- Local reasoning: Gemma 4 generates spending summaries, health-spending insights, and 7-day action plans on the iPhone.

The core privacy goal is simple: sensitive spending and health data should not need to leave the user's phone for the main analysis flow.

## Core Demo Flow

1. Load demo spending data.
2. Review monthly health-aware spending status on Today.
3. Run Fin Assistant for a selected month.
4. Scan or upload a lab report in Health Scan.
5. Review extracted health markers and evidence.
6. Generate Insights linking spending behavior to health markers.
7. Show the 7-Day Action Plan with movement and food recommendations.

## Features

### Today

- Shows current readiness for finance, health, and insight generation.
- Displays a health-aware spending score after demo data is loaded.
- Routes the user to the next useful action.

### Spending

- Supports month-by-month spending review.
- Demo data covers 2026/01 through 2026/05.
- Categories include Food Delivery, Fast Food, Convenience Store, Groceries, Sugary Drinks, Coffee, Dining Out, Entertainment, Late Night, and Other.

### Fin Assistant

- Runs local Gemma 4 text inference through Cactus.
- Lets the user choose the analysis month directly inside the Fin Assistant page.
- Produces a spending breakdown, budget levers, a 7-day recommendation, and markdown-style AI notes.
- Caches results by month so switching months does not erase previous analysis.

### Health Scan

- Supports camera capture and photo library upload.
- Attempts Gemma 4 vision extraction first.
- If direct vision extraction is incomplete or memory constrained, the app releases the model, runs Apple Vision OCR, reloads Gemma 4, and uses local text inference to structure the OCR into health metrics.
- Keeps Apple Vision OCR as a fallback for demo stability.

### Health Results

- Displays extracted metrics, status, ranges, and patient-friendly evidence trace.
- Routes directly to Insights after health data exists.

### Insights

- Uses the same selected AI analysis month as Fin Assistant.
- Runs local Gemma 4 inference through Cactus.
- Produces:
  - overall risk score
  - monthly spending at risk
  - signal path
  - 7-Day Action Plan
  - key findings with concrete actions
- Caches insight results by month.

## Architecture

```text
Spendy iOS App
  SwiftUI UI
    Today
    Spending
    Fin Assistant
    Health Scan
    Health Results
    Insights

  App State
    Spending entries
    Health report
    Monthly finance summaries
    Monthly insight results
    Shared analysis month

  Service Router
    Mock providers
    Remote providers
    On-device providers

  On-device providers
    Finance summary provider
    Health report extractor
    Insight generator

  Cactus Runtime
    Gemma 4 E2B local inference
    Text completion
    Vision completion when memory allows
```

## Model And Runtime

Runtime:

- Cactus iOS runtime
- Local model loading through `cactus-ios.xcframework`
- Serial inference queue in `CactusManager`

Base model:

- `google/gemma-4-E2B-it`
- Hugging Face: https://huggingface.co/google/gemma-4-E2B-it

Fine-tuned / LoRA model:

- `EddieTsai123/gemma_4_e2b_lora`
- Hugging Face: https://huggingface.co/EddieTsai123/gemma_4_e2b_lora

Related converted model page:

- `EddieTsai123/gemma-4-e2b-m23k-cot-sft-lora`
- Hugging Face: https://huggingface.co/EddieTsai123/gemma-4-e2b-m23k-cot-sft-lora

Local Cactus weights folder expected by the app:

```text
Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/
```

Expected final size is roughly 4.5 GB.

## Repository Layout

Expected local layout:

```text
Gemma4Good/
  cactus/
    apple/cactus-ios.xcframework
    weights/gemma-4-e2b-m23k-cot-sft-lora-int4/
  Spendy/
    ios/Spendy.xcodeproj
```


## System Requirements

Required:

- macOS with Xcode installed
- Physical iPhone with Developer Mode enabled
- Command Line Tools
- Homebrew
- Git LFS
- Python 3.12
- CMake
- Hugging Face access to the base and fine-tuned model repositories
- At least 60 GB free disk space if converting weights locally

Install baseline tools:

```bash
xcode-select --install
brew install cmake python@3.12 git-lfs
git lfs install
```

Open Xcode once and install required iOS components.

If needed:

```bash
sudo xcodebuild -license accept
```

## Clone

```bash
mkdir -p ~/Gemma4Good
cd ~/Gemma4Good
git clone https://github.com/cactus-compute/cactus.git cactus
git clone https://github.com/Gemma4Hackathon/Spendy.git Spendy
cd Spendy
git checkout main
```

## Set Up Cactus

```bash
cd ~/Gemma4Good/cactus
source ./setup
python -m pip install -e "./python[lora]"
```

Confirm:

```bash
cactus --help
```

Install and authenticate Hugging Face CLI if converting weights:

```bash
curl -LsSf https://hf.co/cli/install.sh | bash -s
hf auth login
hf auth whoami
```

## Build Cactus iOS Framework

```bash
cd ~/Gemma4Good/cactus
./apple/build.sh
```

Expected artifacts:

```text
apple/cactus-ios.xcframework
apple/libcactus-device.a
apple/libcactus-simulator.a
```

The Spendy Xcode project expects:

```text
~/Gemma4Good/cactus/apple/cactus-ios.xcframework
```

## Prepare Local Model Weights

### Option A: Copy Converted Weights

Use this if a teammate already converted the model:

```bash
mkdir -p ~/Gemma4Good/cactus/weights
cp -R /path/to/gemma-4-e2b-m23k-cot-sft-lora-int4 \
  ~/Gemma4Good/cactus/weights/
```

Validate:

```bash
ls ~/Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
du -sh ~/Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4
```

### Option B: Convert From Hugging Face

```bash
cd ~/Gemma4Good/cactus
source ./venv/bin/activate

cactus convert google/gemma-4-E2B-it \
  ./weights/gemma-4-e2b-m23k-cot-sft-lora-int4 \
  --lora EddieTsai123/gemma_4_e2b_lora \
  --precision INT4
```

Validate:

```bash
ls ./weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
du -sh ./weights/gemma-4-e2b-m23k-cot-sft-lora-int4
```

If conversion is killed, check disk space:

```bash
df -h ~/Gemma4Good
```

The base model download and LoRA merge can temporarily require much more space than the final INT4 folder.

## Build And Run Spendy

Open the Xcode project:

```bash
open ~/Gemma4Good/Spendy/ios/Spendy.xcodeproj
```

In Xcode:

1. Select target `Spendy`.
2. Open Signing & Capabilities.
3. Set your Apple development team.
4. Set a unique Bundle Identifier if needed.
5. Select a physical iPhone.
6. Make sure the iPhone is unlocked, trusted, and Developer Mode is enabled.
7. Build and run.

The app defaults to on-device mode in:

```text
ios/App/SpendyApp.swift
```

Expected model load log:

```text
[CactusManager] Using bundled model: gemma-4-e2b-m23k-cot-sft-lora-int4
[CactusManager] Model ready.
```

Expected Cactus fallback warnings:

```text
[WARN] [npu] [gemma4-vision] vision_encoder.mlpackage not found; using CPU vision encoder
[WARN] [npu] [gemma4-audio] audio_encoder.mlpackage not found; using CPU audio encoder
[WARN] [npu] [gemma4] model.mlpackage not found; using CPU prefill
```

These warnings are acceptable for the current demo. They mean Core ML `.mlpackage` accelerators are not bundled, so Cactus falls back to CPU paths.

## Command Line Build Check

From the Spendy repo root:

```bash
xcodebuild \
  -project ios/Spendy.xcodeproj \
  -scheme Spendy \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected:

```text
** BUILD SUCCEEDED **
```

## Demo Script

Use this flow for a judge-facing live demo:

1. Launch Spendy and wait for `Model ready`.
2. Open Profile and tap `Load Finance Demo`.
3. Open Today and show the health-aware spending score.
4. Open Fin Assistant.
5. Select `2026 / 05`.
6. Tap refresh and show the local spending analysis.
7. Open Health Scan.
8. Use `Take Photo` or `Choose from Library` with the sample lab report.
9. Show the extracted Health Results and evidence trace.
10. Tap `Go to Insights`.
11. Generate Insights for the same analysis month.
12. Show Signal Path, 7-Day Action Plan, and Key Findings.

Recommended demo language:

```text
Spendy runs Gemma 4 locally on the iPhone through Cactus.
The main finance and insight reasoning flows do not require sending user health or spending data to a cloud LLM.
Health Scan attempts Gemma 4 vision first, and falls back to Apple Vision OCR plus local Gemma text structuring when mobile memory is constrained.
```

Avoid claiming that on-device inference is always faster than cloud inference. The current value proposition is privacy, offline-capable reasoning, and a working mobile prototype.

## Expected Runtime Logs

Fin Assistant:

```text
[CactusManager] Inference queued (maxTokens: 650)...
[CactusManager] Inference done (...)
```

Health Scan, best case:

```text
[HealthExtractor] Trying Gemma 4 vision extraction...
[CactusManager] Vision inference done (...)
[HealthExtractor] Raw model text received (...)
```

Health Scan, memory-constrained fallback:

```text
[HealthExtractor] Gemma 4 vision failed. Releasing model before Apple Vision OCR...
[CactusManager] Model released.
[HealthExtractor] OCR recovery text recognized (...)
[CactusManager] Model ready.
[CactusManager] Inference queued (maxTokens: 1600)...
```

Insights:

```text
[InsightGenerator] Starting on-device inference...
[CactusManager] Inference queued (maxTokens: 1200)...
[InsightGenerator] Parsed 2 findings...
```

Common iOS/Xcode system logs that can be ignored if the app continues:

```text
Failed to send CA Event for app launch measurements
personaAttributesForPersonaType ... connection invalidated
LaunchServices ... process may not map database
RTIInputSystemClient ... requires a valid sessionID
Reporter disconnected
```

Logs that matter:

- `Model ready`: local inference is available.
- `std::bad_alloc`: image inference exceeded available runtime memory; fallback should continue.
- `Parsed 2 findings`: Insight generation succeeded.

## Competition Submission Checklist

For a complete Gemma 4 Good Hackathon submission, include:

- Kaggle writeup with product problem, architecture, model choice, limitations, and demo instructions.
- Public code repository with this README.
- Public video showing the human use case.
- Attached live demo link or downloadable demo package.
- Media gallery with clear screenshots and short clips.
- Technical analysis explaining how Gemma 4 is used.

Recommended attached live demo package:

```text
Spendy-live-demo/
  README-demo.md
  sample-health-report.pdf
  sample-health-report.png
  screenshots/
    01_today.png
    02_fin_assistant.png
    03_health_scan.png
    04_health_results.png
    05_insights_signal_path.png
    06_insights_action_plan.png
  clips/
    01_load_demo.mov
    02_fin_assistant.mov
    03_health_scan.mov
    04_insights.mov
```

Recommended media gallery:

1. Today page after loading demo data.
2. Fin Assistant monthly analysis.
3. Health Scan camera or upload entry point.
4. Health Results extracted metrics.
5. Insights Signal Path.
6. 7-Day Action Plan.

## Technical Notes

### Why Cactus

Cactus gives the app a local runtime for Gemma 4 on iPhone. This supports:

- local text inference
- local vision inference when memory allows
- offline-capable demo behavior
- privacy-preserving processing for sensitive user data

### Why Apple Vision OCR fallback exists

Mobile image inference can hit runtime memory pressure, especially when the app already has a local LLM loaded. Spendy keeps the product reliable by:

1. Trying Gemma 4 vision extraction.
2. Detecting failed or incomplete extraction.
3. Releasing the model before OCR if memory pressure occurs.
4. Running Apple Vision OCR.
5. Reloading Gemma 4 for text structuring.
6. Returning the best available health report.

This makes the demo stable while still showing Gemma 4 in the health extraction pipeline.

### Privacy stance

Default console logs avoid printing full OCR text, health values, or spending prompt contents. Verbose sensitive logs require the `SPENDY_VERBOSE_LOGS` compilation flag.

### Medical safety

Spendy is a behavioral guidance prototype. It is not a medical device and does not provide diagnosis or treatment. Output should be interpreted as educational guidance that may help users discuss patterns with clinicians or health professionals.

## Optional Cactus Test Suite

This is optional for Spendy app development. It is useful after changing Cactus or model packaging.

Required weights for LLM-only test:

```text
cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4
cactus/weights/parakeet-tdt-0.6b-v3
cactus/weights/whisper-small
cactus/weights/silero-vad
cactus/weights/segmentation-3.0
cactus/weights/wespeaker-voxceleb-resnet34-lm
```

Run:

```bash
cd ~/Gemma4Good/cactus
source ./venv/bin/activate

DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
cactus test \
  --model gemma-4-e2b-m23k-cot-sft-lora-int4 \
  --ios \
  --llm
```

If the multiple-tool-call test fails but the other LLM tests pass, Spendy can still run local inference. That test checks generic multi-tool-calling behavior, not the Spendy app flow.

## Troubleshooting

### Xcode shows device offline

```bash
xcrun xctrace list devices
```

Then:

1. Unlock iPhone.
2. Reconnect USB.
3. Trust this computer.
4. Enable Developer Mode.
5. Restart Xcode.

### Could not extract Team ID from certificate

Pass it explicitly:

```bash
DEVELOPMENT_TEAM=<YOUR_TEAM_ID> cactus test --model gemma-4-e2b-m23k-cot-sft-lora-int4 --ios --llm
```

### Model folder not found

Check:

```bash
ls ~/Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
```

The folder name must match:

```text
gemma-4-e2b-m23k-cot-sft-lora-int4
```

### Health Scan returns too few metrics

Use a clear, flat, well-lit image of the report. If using the camera, keep the page parallel to the phone and avoid glare.

The fallback path may still return fewer metrics if OCR text quality is poor. The demo should use the supplied sample report image when consistency matters.

### `std::bad_alloc` during Health Scan

This can happen during direct Gemma 4 vision extraction. It is expected on memory-constrained runs if fallback continues. The app should release the model and continue through OCR recovery.

If the app crashes or fallback does not continue, clean build and reinstall:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Spendy-*
```

### Gemini API key

Gemini is not required for the main local demo flow. The front-end currently hides image generation during demo because it is not part of the validated local inference path.

## Clean Rebuild

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Spendy-*

cd ~/Gemma4Good/cactus
./apple/build.sh

cd ~/Gemma4Good/Spendy
xcodebuild \
  -project ios/Spendy.xcodeproj \
  -scheme Spendy \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```
