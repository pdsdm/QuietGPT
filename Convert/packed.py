import os

import numpy as np
from lone import runtime
from lone.runtime import LoneModel


class PackedModel(LoneModel):
    def __init__(self, bundle_dir, compute_units="cpu_and_ne"):
        load = runtime.np.load
        runtime.np.load = lambda path, **kw: None if str(path).endswith(".q8") else load(path, **kw)
        try:
            super().__init__(bundle_dir, compute_units)
        finally:
            runtime.np.load = load
        emb = self.manifest["embedding"]
        shape = (emb["vocab"], emb["hidden"])
        self._q = np.memmap(os.path.join(bundle_dir, emb["file"]), dtype=np.int8, mode="r", shape=shape)
        self._scale = np.fromfile(os.path.join(bundle_dir, emb["scale"]), dtype=np.float16).astype(np.float32)

    def _embed_tokens(self, ids):
        rows = np.asarray(ids, dtype=np.int64)
        values = self._q[rows].astype(np.float32) * self._scale[rows][:, None]
        return values.astype(np.float16)[None]

    def _run_chunk(self, chunk, tag, hidden, pos):
        if tag not in chunk["models"]:
            import coremltools as ct

            model = ct.models.MLModel(chunk["paths"][tag], compute_units=self._units, function_name=tag)
            self._compiled.append(model.get_compiled_model_path())
            chunk["models"][tag] = model
        super()._run_chunk(chunk, tag, hidden, pos)
