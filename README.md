# Spendy iOS Setup

This project is an iOS SwiftUI app that runs Gemma 4 E2B locally through Cactus.

Expected repo layout:

```text
Gemma4Good/
  cactus/
  Spendy/
```

The Xcode project expects:

```text
Gemma4Good/cactus/apple/cactus-ios.xcframework
Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/
```

## 1. System Requirements

Install:

```bash
xcode-select --install
brew install cmake python@3.12 git-lfs
git lfs install
```

Open Xcode once and install required iOS components.

Accept Xcode license if needed:

```bash
sudo xcodebuild -license accept
```

You need Hugging Face access to:

```text
google/gemma-4-E2B-it
EddieTsai123/gemma_4_e2b_lora
```

Recommended free disk space before conversion: at least 60 GB.

## 2. Clone

```bash
mkdir -p ~/Gemma4Good
cd ~/Gemma4Good
git clone https://github.com/cactus-compute/cactus.git cactus
git clone https://github.com/Gemma4Hackathon/Spendy.git Spendy
cd Spendy
git checkout feat/ios-optimization
```

If the repos are already inside one mono-repo, clone that repo and keep this layout:

```text
Gemma4Good/cactus
Gemma4Good/Spendy
```

## 3. Set Up Cactus CLI

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

## 4. Build Cactus iOS Framework

```bash
cd ~/Gemma4Good/cactus
./apple/build.sh
```

Expected output:

```text
apple/cactus-ios.xcframework
apple/libcactus-device.a
apple/libcactus-simulator.a
```

If CMake complains about vendored libcurl, verify:

```bash
ls ~/Gemma4Good/cactus/libs/curl/include/curl/curl.h
ls ~/Gemma4Good/cactus/libs/curl/android
```

For iOS app builds, the required artifact is:

```text
~/Gemma4Good/cactus/apple/cactus-ios.xcframework
```

## 5. Prepare Local Model Weights

### Option A: Copy Existing Converted Weights

Fastest path if another teammate already converted the model:

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

Expected size is roughly 4.5 GB.

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

If conversion is killed:

```bash
df -h ~/Gemma4Good
```

Free more disk space and rerun. The base model download and LoRA merge can temporarily use much more space than the final INT4 folder.

## 6. Open Spendy in Xcode

```bash
open ~/Gemma4Good/Spendy/ios/Spendy.xcodeproj
```

In Xcode:

1. Select target `Spendy`.
2. Go to Signing & Capabilities.
3. Set your own Team.
4. Set a unique Bundle Identifier if needed.
5. Select a physical iPhone.
6. Make sure the iPhone is unlocked, trusted, and Developer Mode is enabled.

The app currently defaults to on-device mode in:

```text
ios/App/SpendyApp.swift
```

Expected model load log:

```text
[CactusManager] Using bundled model: gemma-4-e2b-m23k-cot-sft-lora-int4
[CactusManager] Model ready.
```

These warnings are acceptable:

```text
[WARN] [npu] [gemma4-vision] vision_encoder.mlpackage not found; using CPU vision encoder
[WARN] [npu] [gemma4-audio] audio_encoder.mlpackage not found; using CPU audio encoder
[WARN] [npu] [gemma4] model.mlpackage not found; using CPU prefill
```

## 7. Command Line Build Check

From repo root:

```bash
cd ~/Gemma4Good
xcodebuild \
  -project Spendy/ios/Spendy.xcodeproj \
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

## 8. App Test Flow

Run the app from Xcode on iPhone.

Use this flow:

1. Wait for model ready.
2. Go to Profile.
3. Tap `Load Finance Demo`.
4. Go to Today.
5. Confirm Health-aware spending score appears.
6. Go to Fin Assistant.
7. Confirm the assistant returns local analysis and spending chart.
8. Go to Health Scan.
9. Upload or take a photo of a lab report.
10. Confirm OCR extraction and health result screen.
11. Go to Insights.
12. Generate insight after finance and health data exist.

Health Scan uses Apple Vision OCR first, then local parsing/text-only local model fallback. It should not call Cactus image inference.

Expected Health Scan log:

```text
[HealthExtractor] OCR text ...
```

Unexpected old failure log:

```text
[CactusManager] Vision inference queued...
[ERROR] [complete] Exception: std::bad_alloc
```

If this appears, the app is running an old build. Clean build and reinstall.

## 9. Cactus iOS Test Suite

This is optional for Spendy app development, but useful after changing Cactus or model packaging.

Required weights for LLM-only test:

```text
cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4
cactus/weights/parakeet-tdt-0.6b-v3
cactus/weights/whisper-small
cactus/weights/silero-vad
cactus/weights/segmentation-3.0
cactus/weights/wespeaker-voxceleb-resnet34-lm
```

Current local sizes:

```text
gemma-4-e2b-m23k-cot-sft-lora-int4  ~4.6G
parakeet-tdt-0.6b-v3               ~750M
whisper-small                      ~244M
silero-vad                         ~664K
segmentation-3.0                   ~3M
wespeaker-voxceleb-resnet34-lm     ~14M
```

Run LLM-only test:

```bash
cd ~/Gemma4Good/cactus
source ./venv/bin/activate

DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
cactus test \
  --model gemma-4-e2b-m23k-cot-sft-lora-int4 \
  --ios \
  --llm
```

If the multiple-tool-call test fails but the other LLM tests pass, Spendy can still run local inference. That test checks a generic multi-tool-calling behavior, not the Spendy app flow.

## 10. Common Issues

### Xcode shows device offline

Check:

```bash
xcrun xctrace list devices
```

Fix:

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

Find Team ID in Apple Developer account or Xcode signing settings.

### Provisioning paramter list / No provider was found

This warning can appear during `devicectl` install/launch. If the app installs and launches, ignore it.

### `std::bad_alloc` during Health Scan

The app should not use Cactus image inference for Health Scan. Clean build:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Spendy-*
```

Then rerun from Xcode.

### Model folder not found

Check:

```bash
ls ~/Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
```

The folder name must match exactly:

```text
gemma-4-e2b-m23k-cot-sft-lora-int4
```

### Gemini API key

Gemini is not required for local Fin Assistant, Health Scan OCR, or Insights. It is used only for remote/provider experiments and body visualization image generation.

Set it in Profile if needed.

## 11. Useful Paths

```text
Spendy/ios/App/SpendyApp.swift
Spendy/ios/App/AppState.swift
Spendy/ios/App/MainTabView.swift
Spendy/ios/Services/CactusManager.swift
Spendy/ios/Services/Providers/OnDevice/
Spendy/ios/Features/FinanceAssistant/
Spendy/ios/Features/HealthScan/
Spendy/ios/Features/HealthResults/
Spendy/ios/Features/Insights/
cactus/weights/
cactus/apple/cactus-ios.xcframework
```

## 12. Clean Rebuild

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Spendy-*

cd ~/Gemma4Good/cactus
./apple/build.sh

cd ~/Gemma4Good
xcodebuild \
  -project Spendy/ios/Spendy.xcodeproj \
  -scheme Spendy \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```
