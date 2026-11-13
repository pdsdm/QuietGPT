#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
precision="${1:-lut8}"
ctx="${2:-1024}"
if [[ ! -d .venv ]]; then
  uv venv -q --python 3.13 .venv
  uv pip install -q --python .venv/bin/python -r requirements.txt
fi
model="$(.venv/bin/hf download LiquidAI/LFM3-1.7B 2>/dev/null | tail -1 | sed 's/^path=//')"
.venv/bin/lone convert --model "$model" --out "bundles/lfm3-$precision-$ctx" --ctx "$ctx" --prefill 64 --precision "$precision"
