import argparse
import importlib.util
import json
import os
import subprocess
import sys
import time

import numpy as np


def load_prompts(path, limit):
    items = [json.loads(line) for line in open(path) if line.strip()]
    return items[:limit] if limit else items


def load_system(path, name):
    spec = importlib.util.spec_from_file_location("phase0_prompts", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return getattr(module, name)


def reference(args):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(args.model, local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(
        args.model, dtype=torch.float32, local_files_only=True, trust_remote_code=True
    )
    model.eval()
    system = load_system(args.system_file, args.system_name)
    out = []
    for item in load_prompts(args.prompts, args.limit):
        messages = [{"role": "system", "content": system}, {"role": "user", "content": item["text"]}]
        text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True, enable_thinking=False)
        prompt_ids = tokenizer(text, add_special_tokens=False)["input_ids"]
        with torch.no_grad():
            sequence = model.generate(torch.tensor([prompt_ids]), do_sample=False, max_new_tokens=args.new_tokens)[0]
            logits = model(sequence[None]).logits[0]
        top2 = torch.topk(logits, 2, dim=-1)
        out.append({
            "id": item["id"],
            "ids": sequence.tolist(),
            "prompt_len": len(prompt_ids),
            "argmax": top2.indices[:, 0].tolist(),
            "margin": (top2.values[:, 0] - top2.values[:, 1]).tolist(),
        })
        print(f"reference {item['id']}: {len(prompt_ids)} + {len(sequence) - len(prompt_ids)} tokens", flush=True)
    json.dump(out, open(args.reference, "w"))


def bundle(args):
    from lone.runtime import LoneModel

    model = LoneModel(args.bundle, args.compute_units)
    items = json.load(open(args.reference))
    rows = []
    for item in items:
        ids, n, ref = item["ids"], item["prompt_len"], item["argmax"]
        for mode in ("decode", "prefill"):
            model.reset()
            got = [None] * len(ids)
            start = 0
            if mode == "prefill":
                full = (n // model.prefill_len) * model.prefill_len
                if full:
                    model.feed(ids[:full])
                    got[full - 1] = int(np.argmax(model._logits_all(model._hidden[:, -1:, :])[-1]))
                    start = full
            began = time.time()
            for position in range(start, len(ids)):
                got[position] = int(np.argmax(model.step(ids[position])))
            seconds = time.time() - began
            checked = [p for p in range(len(ids)) if got[p] is not None]
            reply = [p for p in checked if p >= n - 1]
            misses = [p for p in checked if got[p] != ref[p]]
            rows.append({
                "id": item["id"],
                "mode": mode,
                "positions": len(checked),
                "matches": len(checked) - len(misses),
                "reply_positions": len(reply),
                "reply_matches": sum(got[p] == ref[p] for p in reply),
                "miss_margins": [round(item["margin"][p], 3) for p in misses],
                "decode_tok_s": round((len(ids) - start) / seconds, 1),
            })
            print(f"{item['id']:<12} {mode:<7} {rows[-1]['matches']}/{rows[-1]['positions']}  "
                  f"reply {rows[-1]['reply_matches']}/{rows[-1]['reply_positions']}  "
                  f"{rows[-1]['decode_tok_s']} tok/s  misses at margin {rows[-1]['miss_margins']}", flush=True)
    for mode in ("decode", "prefill"):
        part = [r for r in rows if r["mode"] == mode]
        total = sum(r["positions"] for r in part)
        good = sum(r["matches"] for r in part)
        reply_total = sum(r["reply_positions"] for r in part)
        reply_good = sum(r["reply_matches"] for r in part)
        margins = [m for r in part for m in r["miss_margins"]]
        speed = np.median([r["decode_tok_s"] for r in part])
        print(f"{mode}: top token {good}/{total} = {100 * good / total:.2f}%  "
              f"reply {reply_good}/{reply_total} = {100 * reply_good / reply_total:.2f}%  "
              f"median miss margin {np.median(margins) if margins else 0:.3f}  median {speed} tok/s")
    if args.out:
        json.dump(rows, open(args.out, "w"), indent=1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--system-file", required=True)
    parser.add_argument("--system-name", default="LFM_V1_INSTRUCTIONS")
    parser.add_argument("--reference", required=True)
    parser.add_argument("--new-tokens", type=int, default=64)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--compute-units", default="cpu_and_ne")
    parser.add_argument("--out", default="")
    parser.add_argument("--phase", default="all", choices=["all", "reference", "bundle"])
    args = parser.parse_args()
    if args.phase == "reference" or (args.phase == "all" and not os.path.exists(args.reference)):
        if args.phase == "all":
            subprocess.run([sys.executable, __file__, *sys.argv[1:], "--phase", "reference"], check=True)
        else:
            reference(args)
    if args.phase in ("all", "bundle"):
        bundle(args)


if __name__ == "__main__":
    main()
