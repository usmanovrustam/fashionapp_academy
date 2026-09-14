#!/usr/bin/env python3
"""Export mattmdjaga/segformer_b2_clothes to Core ML for Nook on-device scanning.

Prefer `scripts/build_strong_clothes_coreml.py` to collect multiple HF teachers
and produce one stronger Core ML package (distill or best-atr).
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from transformers import SegformerForSemanticSegmentation


LABELS = [
    "Background",
    "Hat",
    "Hair",
    "Sunglasses",
    "Upper-clothes",
    "Skirt",
    "Pants",
    "Dress",
    "Belt",
    "Left-shoe",
    "Right-shoe",
    "Face",
    "Left-leg",
    "Right-leg",
    "Left-arm",
    "Right-arm",
    "Bag",
    "Scarf",
]


class SegformerLogits(torch.nn.Module):
    def __init__(self, model: SegformerForSemanticSegmentation):
        super().__init__()
        self.model = model

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.model(pixel_values=pixel_values).logits


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("fashionapp/ClothesSegFormer.mlpackage"),
    )
    parser.add_argument("--size", type=int, default=512)
    args = parser.parse_args()

    repo = "mattmdjaga/segformer_b2_clothes"
    print(f"Loading {repo}…", flush=True)
    model = SegformerForSemanticSegmentation.from_pretrained(repo)
    model.eval()

    wrapper = SegformerLogits(model)
    wrapper.eval()

    size = args.size
    example = torch.randn(1, 3, size, size)
    print(f"Tracing at {size}x{size}…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
        traced = torch.jit.freeze(traced)

    print("Converting to Core ML (mlprogram, float16, MultiArray input)…", flush=True)
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="pixel_values",
                shape=(1, 3, size, size),
                dtype=np.float32,
            )
        ],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )

    # Stable output name for the iOS client.
    try:
        from coremltools.models.utils import rename_feature

        spec = mlmodel.get_spec()
        out_name = spec.description.output[0].name
        if out_name != "logits":
            rename_feature(spec, out_name, "logits")
            weights = args.out / "Data" / "com.apple.CoreML" / "weights"
            # Save via temp then rename after first write below.
            mlmodel = ct.models.MLModel(spec)
    except Exception as exc:  # noqa: BLE001
        print(f"Warning: could not rename output to logits ({exc})", flush=True)

    mlmodel.author = "Nook"
    mlmodel.license = "See upstream model card: mattmdjaga/segformer_b2_clothes"
    mlmodel.short_description = (
        "SegFormer-B2 clothes segmentation (ATR 18 classes). "
        "Labels: " + ", ".join(f"{i}:{n}" for i, n in enumerate(LABELS))
    )
    mlmodel.version = "1.0.0"

    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.exists():
        shutil.rmtree(args.out)
    mlmodel.save(str(args.out))

    # Ensure logits name survives package save (mlprogram).
    try:
        from coremltools.models.utils import rename_feature

        packaged = ct.models.MLModel(str(args.out))
        spec = packaged.get_spec()
        out_name = spec.description.output[0].name
        if out_name != "logits":
            rename_feature(spec, out_name, "logits")
            weights_dir = args.out / "Data" / "com.apple.CoreML" / "weights"
            renamed = ct.models.MLModel(spec, weights_dir=str(weights_dir))
            tmp = args.out.parent / (args.out.name + ".tmp")
            if tmp.exists():
                shutil.rmtree(tmp)
            renamed.save(str(tmp))
            shutil.rmtree(args.out)
            tmp.rename(args.out)
            print("Renamed output feature → logits", flush=True)
    except Exception as exc:  # noqa: BLE001
        print(f"Warning: post-save rename skipped ({exc})", flush=True)

    print(f"Saved {args.out}", flush=True)

    labels_path = args.out.parent / "ClothesSegFormerLabels.json"
    labels_path.write_text(json.dumps({"labels": LABELS, "input_size": size}, indent=2))
    print(f"Saved {labels_path}", flush=True)


if __name__ == "__main__":
    main()
