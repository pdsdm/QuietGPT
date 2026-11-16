#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="${1:-bundles/lfm3-lut8-dyn-app}"
work="${TMPDIR:-/tmp}/quietgpt-coreml-check"
mkdir -p "$work/llama"
prefix="$(brew --prefix llama.cpp)"
print "module llama {\n  header \"$prefix/include/llama.h\"\n  link \"llama\"\n  export *\n}" > "$work/llama/module.modulemap"
app=../QuietGPT/Core/Reply
xcrun swiftc -O -I "$work" -Xcc -I/opt/homebrew/include -L "$prefix/lib" -Xlinker -rpath -Xlinker "$prefix/lib" \
  $app/CoreML/CoreMLBundle.swift $app/CoreML/CoreMLMath.swift $app/CoreML/CoreMLSampler.swift $app/CoreML/CoreMLCore.swift \
  $app/Llama/LlamaVocab.swift $app/EngineMetrics.swift swift/main.swift -o "$work/check"
research=../../QuietRESEARCH/phase0
if [[ ! -f "$work/reference.json" ]]; then
  .venv/bin/python swift_reference.py --bundle "$bundle" --prompts "$research/prompts.jsonl" --system-file "$research/prompts.py" --out "$work/reference.json"
fi
"$work/check" "$bundle" "$work/reference.json" "$work/compiled-$(basename "$bundle")"
