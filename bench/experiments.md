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
