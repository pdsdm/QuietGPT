import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundles", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    import coremltools as ct

    sources = [Path(b) for b in args.bundles]
    manifests = [json.loads((s / "manifest.json").read_text()) for s in sources]
    contexts = [m["shapes"]["ctx"] for m in manifests]
    if contexts != sorted(contexts):
        raise SystemExit("bundles must be in growing context order")
    out = Path(args.out)
    if out.exists():
        raise SystemExit(f"{out} exists")
    began = time.time()
    base = manifests[0]
    (out / "chunks").mkdir(parents=True)
    for index, chunk in enumerate(base["chunks"]):
        descriptor = ct.utils.MultiFunctionDescriptor()
        for source, manifest, ctx in zip(sources, manifests, contexts):
            other = manifest["chunks"][index]
            for tag, meta in other["models"].items():
                descriptor.add_function(str(source / meta["file"]), meta["function"], f"{tag}_{ctx}")
        descriptor.default_function_name = f"decode_{contexts[0]}"
        target = Path("chunks") / f"{chunk['name']}.mlpackage"
        ct.utils.save_multifunction(descriptor, str(out / target))
        for tag, meta in chunk["models"].items():
            meta["file"] = str(target)
            meta["function"] = f"{tag}_{contexts[0]}"
        print(f"{chunk['name']}: {len(contexts) * len(chunk['models'])} functions", flush=True)
    first = sources[0]
    for name in ["head", base["tokenizer"]["dir"]]:
        shutil.copytree(first / name, out / name)
    for name in [base["embedding"]["file"], base["embedding"]["scale"], "tokenizer.gguf"]:
        shutil.copy2(first / name, out / name)
    base["contexts"] = contexts
    base["packed_from"] = [s.name for s in sources]
    base["pack_seconds"] = round(time.time() - began, 1)
    (out / "manifest.json").write_text(json.dumps(base, indent=2))
    size = subprocess.run(["du", "-sh", str(out)], capture_output=True, text=True).stdout.split()[0]
    print(f"{out}: contexts {contexts}, {size}, {base['pack_seconds']} s", flush=True)


if __name__ == "__main__":
    main()
