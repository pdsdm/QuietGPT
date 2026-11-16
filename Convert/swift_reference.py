import argparse
import importlib.util
import json

import numpy as np
from transformers import AutoTokenizer

from packed import PackedModel


def load_system(path, name):
    spec = importlib.util.spec_from_file_location("phase0_prompts", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--system-file", required=True)
    parser.add_argument("--system-name", default="LFM_V1_INSTRUCTIONS")
    parser.add_argument("--limit", type=int, default=6)
    parser.add_argument("--new-tokens", type=int, default=48)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    tokenizer = AutoTokenizer.from_pretrained(f"{args.bundle}/tokenizer")
    system = load_system(args.system_file, args.system_name)
    items = [json.loads(line) for line in open(args.prompts) if line.strip()][: args.limit]
    cases = []
    for item in items:
        messages = [{"role": "system", "content": system}, {"role": "user", "content": item["text"]}]
        text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
        cases.append({"id": item["id"], "text": text, "ids": tokenizer(text, add_special_tokens=False)["input_ids"]})
    base = cases[0]["ids"]
    for n in (64, 128, 65):
        cases.append({"id": f"cut-{n}", "text": None, "ids": base[:n]})
    model = PackedModel(args.bundle)
    for case in cases:
        model.reset()
        model.feed(case["ids"])
        logits = model._logits_all(model._hidden[:, -1:, :])[-1]
        greedy = []
        for _ in range(args.new_tokens):
            token = int(np.argmax(logits))
            greedy.append(token)
            logits = model.step(token)
        case["greedy"] = greedy
        print(case["id"], len(case["ids"]), flush=True)
    json.dump(cases, open(args.out, "w"))


if __name__ == "__main__":
    main()
