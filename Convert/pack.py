import argparse
import json
import shutil
import time
from pathlib import Path

import numpy as np


def merge(target, functions, default):
    import coremltools as ct

    descriptor = ct.utils.MultiFunctionDescriptor()
    for name, path in functions.items():
        descriptor.add_function(str(path), "main", name)
    descriptor.default_function_name = default
    ct.utils.save_multifunction(descriptor, str(target))


def quantize_embedding(source, target_dir):
    table = np.load(source, mmap_mode="r")
    vocab, hidden = table.shape
    q = np.empty((vocab, hidden), dtype=np.int8)
    scale = np.empty(vocab, dtype=np.float16)
    error = 0.0
    for start in range(0, vocab, 8192):
        rows = np.asarray(table[start:start + 8192], dtype=np.float32)
        peak = np.abs(rows).max(axis=1)
        s = np.where(peak > 0, peak / 127.0, 1.0).astype(np.float16)
        values = np.clip(np.rint(rows / s.astype(np.float32)[:, None]), -127, 127).astype(np.int8)
        q[start:start + 8192] = values
        scale[start:start + 8192] = s
        back = values.astype(np.float32) * s.astype(np.float32)[:, None]
        error = max(error, float((np.abs(back - rows).max(axis=1) / np.maximum(peak, 1e-12)).max()))
    q.tofile(target_dir / "embedding.q8")
    scale.tofile(target_dir / "embedding.scale")
    return {"file": "embedding.q8", "scale": "embedding.scale", "dtype": "int8", "vocab": int(vocab),
            "hidden": int(hidden)}, error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    source = Path(args.bundle)
    out = Path(args.out)
    if out.exists():
        raise SystemExit(f"{out} exists")
    began = time.time()
    manifest = json.loads((source / "manifest.json").read_text())
    (out / "chunks").mkdir(parents=True)
    for chunk in manifest["chunks"]:
        target = Path("chunks") / f"{chunk['name']}.mlpackage"
        functions = {tag: source / meta["file"] for tag, meta in chunk["models"].items()}
        merge(out / target, functions, "decode")
        for tag, meta in chunk["models"].items():
            meta["file"] = str(target)
            meta["function"] = tag
        print(f"{chunk['name']}: {', '.join(functions)}", flush=True)
    shutil.copytree(source / "head", out / "head")
    shutil.copytree(source / manifest["tokenizer"]["dir"], out / manifest["tokenizer"]["dir"])
    manifest["embedding"], error = quantize_embedding(source / manifest["embedding"]["file"], out)
    print(f"embedding: max row error {error:.5f} of the row peak", flush=True)
    manifest["multifunction"] = True
    manifest["packed_from"] = source.name
    manifest["pack_seconds"] = round(time.time() - began, 1)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"{out} in {manifest['pack_seconds']} s", flush=True)


if __name__ == "__main__":
    main()
