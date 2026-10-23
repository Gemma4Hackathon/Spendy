"""Runs one Cactus completion on the Mac with the same options the iPhone app uses.

Lets prompt changes be checked before John runs them on the device: same weights, same
Cactus source (cactus @ d917981f), same greedy options as CactusManager.complete.

Build the library once (outside the cactus repo):
  cmake -S ~/Gemma4Good/cactus/cactus -B <build> -DCMAKE_BUILD_TYPE=Release
  cmake --build <build> --target cactus_ffi -j 8
Run with the cactus venv:
  ~/Gemma4Good/cactus/venv/bin/python bench/mac_insights/run.py \
      --lib <build>/libcactus.dylib --messages messages.json --max-tokens 400 [--out result.json]
`messages.json` is the exact messages JSON the app sends (bench/mac_insights/main.swift).
"""
import argparse
import ctypes
import json
import time
from pathlib import Path

WEIGHTS = Path.home() / "Gemma4Good/cactus/weights/gemma-4-e2b-m23k-cot-sft-lora-int4"
TokenCallback = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_uint32, ctypes.c_void_p)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lib", required=True)
    parser.add_argument("--messages", required=True)
    parser.add_argument("--max-tokens", type=int, required=True)
    parser.add_argument("--out")
    args = parser.parse_args()

    lib = ctypes.CDLL(args.lib)
    lib.cactus_init.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_bool]
    lib.cactus_init.restype = ctypes.c_void_p
    lib.cactus_complete.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_size_t,
        ctypes.c_char_p, ctypes.c_char_p, TokenCallback, ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
    ]
    lib.cactus_complete.restype = ctypes.c_int
    lib.cactus_destroy.argtypes = [ctypes.c_void_p]

    handle = lib.cactus_init(str(WEIGHTS).encode(), None, False)
    if not handle:
        raise SystemExit("cactus_init failed")

    messages = Path(args.messages).read_text()
    # Same options as CactusManager.complete (greedy, repetition penalty off).
    options = json.dumps({"max_tokens": args.max_tokens, "temperature": 0, "top_p": 0.9,
                          "repetition_penalty": 1.0, "auto_handoff": False})
    buf = ctypes.create_string_buffer(1 << 17)
    start = time.time()
    rc = lib.cactus_complete(handle, messages.encode(), buf, len(buf), options.encode(),
                             None, TokenCallback(), None, None, 0)
    elapsed = time.time() - start
    lib.cactus_destroy(handle)
    if rc < 0:
        raise SystemExit(f"cactus_complete failed: {rc}")

    raw = json.loads(buf.value.decode("utf-8", errors="ignore"))
    raw["mac_wall_s"] = round(elapsed, 1)
    if args.out:
        Path(args.out).write_text(json.dumps(raw, indent=1))
    print({k: raw.get(k) for k in ("prefill_tokens", "decode_tokens", "time_to_first_token_ms",
                                   "decode_tps", "mac_wall_s")})
    print(raw.get("response", ""))


if __name__ == "__main__":
    main()
