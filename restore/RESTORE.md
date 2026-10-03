# Restoring the local Spendy + Cactus setup

Snapshot taken 2026-10-03, before the local `~/Gemma4Good` folder was deleted to free disk space.
Goal of this guide: get Spendy building and running on an iPhone again. The re-converted model is **not** guaranteed to be byte-identical to the original 2026-05-14 INT4 model (see "Model notes").

## What is in this folder

| File | Purpose |
|---|---|
| `cactus-d917981f.patch` | Local, uncommitted changes to cactus (LoRA merge/convert path in `python/src/cli.py`, plus `tests/ios/*`). Apply on top of cactus commit `d917981f`. |
| `cactus-ios.xcframework/` | The exact iOS framework Spendy was built against (ios-arm64 + ios-arm64-simulator). Avoids needing to rebuild cactus. |
| `environment.txt` | Commits, Hugging Face revisions, Python package versions at snapshot time. |

## Required folder layout

`ios/Spendy.xcodeproj/project.pbxproj` references the framework and weights with relative paths (`../../cactus/...`), so `Spendy` and `cactus` must be siblings:

```
~/Gemma4Good/
├── Spendy/
└── cactus/
    ├── apple/cactus-ios.xcframework
    └── weights/gemma-4-e2b-m23k-cot-sft-lora-int4/
```

## Steps

### 1. Xcode
Install an Xcode that ships the iOS 26.4 SDK (`IPHONEOS_DEPLOYMENT_TARGET = 26.4`).
```bash
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS
xcodebuild -showsdks | grep -i iphoneos   # must show iphoneos26.4 or newer
```

### 2. Clone both repos
```bash
mkdir -p ~/Gemma4Good && cd ~/Gemma4Good
git clone https://github.com/Gemma4Hackathon/Spendy.git
git clone https://github.com/cactus-compute/cactus.git
cd cactus
git checkout d917981f
git apply ../Spendy/restore/cactus-d917981f.patch
```
Pin `d917981f`: Spendy's `ios/Services/Cactus.swift` calls the cactus C API directly, and newer cactus versions may change it.

### 3. Framework
```bash
mkdir -p ~/Gemma4Good/cactus/apple
cp -R ~/Gemma4Good/Spendy/restore/cactus-ios.xcframework ~/Gemma4Good/cactus/apple/
```
(Alternative: `cd ~/Gemma4Good/cactus && ./apple/build.sh`.)

### 4. Python environment (only needed to convert weights)
```bash
cd ~/Gemma4Good/cactus
/opt/homebrew/opt/python@3.12/bin/python3.12 -m venv venv
source venv/bin/activate
python -m pip install -e "./python[lora]"
hf auth login
```
Exact package versions used originally are in `environment.txt` (notably `transformers` was a dev build from git commit `2ad5a9b8`).

### 5. Convert the model
The Spendy README warns that local conversion needs **at least 60 GB free disk**.
```bash
cd ~/Gemma4Good/cactus && source venv/bin/activate
cactus convert google/gemma-4-E2B-it \
  ./weights/gemma-4-e2b-m23k-cot-sft-lora-int4 \
  --lora EddieTsai123/gemma_4_e2b_lora \
  --precision INT4
ls ./weights/gemma-4-e2b-m23k-cot-sft-lora-int4/config.txt
```

### 6. Build and run
```bash
open ~/Gemma4Good/Spendy/ios/Spendy.xcodeproj
```
Set the signing team, select the physical iPhone (Developer Mode on, trusted), build and run. Use the Release configuration for any memory measurement.

## Model notes

- Original INT4 folder (2026-05-14): 1,959 files, ~4.7 GB. Largest file `embed_tokens_per_layer.weights` ~2.5 GB, `token_embeddings.weights` ~428 MB.
- `google/gemma-4-E2B-it` received commits after 2026-05-14 (chat template, tokenizer_config, README). Converting from today's HEAD will not reproduce the original byte-for-byte.
- The original INT4 folder contained **no** `vision_encoder.mlpackage` / `.mlmodelc`. The separate `weights/gemma-4-e2b-it` folder (base model, no LoRA) did contain `vision_encoder.*` and `audio_encoder.*`. Runtime logs showed `std::bad_alloc` in vision extraction followed by fallback; the missing encoder is the suspected cause (not yet confirmed by a run).

## Notes for the peak-memory measurement

- Cactus loads weights with `mmap(PROT_READ, MAP_SHARED)` (`cactus/graph/graph_io.cpp`). File-backed clean pages are invisible to the Allocations instrument and are not part of the jetsam footprint. Use **VM Tracker** (Dirty Size vs Resident Size), not Allocations alone.
- The project has no `.entitlements` file, so `com.apple.developer.kernel.increased-memory-limit` is not enabled.
- `OnDeviceHealthReportExtractor.extractHealthReport`: vision failure → `releaseModelForMemoryPressure()` → Apple Vision OCR → if direct parsing is insufficient, `reloadModelForTextInference()` loads the model again. The fallback peak may occur at the reload, not at the failure.
- `CactusManager.resolveModelPath()` checks: app bundle → Documents → hardcoded `/Users/weichengchen/Gemma4Good/cactus/weights/...` (only reachable from the Simulator).
- Three phases to measure: model load (`cactusInit`), text inference (`cactusComplete`), vision-failure fallback (whole span). Log `os_proc_available_memory()` at each phase for jetsam headroom.
