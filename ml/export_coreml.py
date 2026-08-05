"""Export the trained multi-task model to a single CoreML .mlpackage.

Input : an RGB image (128x128), pixels 0-255 (CoreML ImageType).
Output: softmax probabilities for category/gender/season/usage/color plus a
        256-d L2-normalized embedding for on-device similarity search.

Normalization (÷255 then ImageNet mean/std) is baked into the graph, so the
iOS side only needs to hand CoreML a CVPixelBuffer — no Vision framework.
"""
from __future__ import annotations

import json
import os

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct

import data as datamod
from model import MultiTaskFashionNet

ART = os.path.join(os.path.dirname(__file__), "artifacts")
TASKS = ["category", "gender", "season", "usage", "color"]
OUT_ORDER = TASKS + ["embedding"]


class ExportModel(nn.Module):
    """Wraps the trained net: 0-1 image in -> softmax probs + embedding out."""

    def __init__(self, net: MultiTaskFashionNet):
        super().__init__()
        self.net = net
        self.register_buffer("mean", torch.tensor(datamod.IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(datamod.IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, x):
        x = (x - self.mean) / self.std
        out = self.net(x)
        probs = [F.softmax(out[t], dim=1) for t in TASKS]
        return (*probs, out["embedding"])


def main():
    ckpt = torch.load(os.path.join(ART, "checkpoint.pt"), map_location="cpu", weights_only=False)
    labels = ckpt["labels"]
    head_dims = ckpt["head_dims"]

    net = MultiTaskFashionNet(head_dims, pretrained=True)
    net.heads.load_state_dict(ckpt["heads"])
    net.eval()

    export = ExportModel(net).eval()
    example = torch.rand(1, 3, datamod.IMG_SIZE, datamod.IMG_SIZE)

    # Torch-side parity check: eager vs traced graph must match before convert.
    with torch.no_grad():
        eager = export(example)
    traced = torch.jit.trace(export, example)
    with torch.no_grad():
        tr = traced(example)
    max_diff = max(float((a - b).abs().max()) for a, b in zip(eager, tr))
    print(f"Torch eager-vs-traced max diff: {max_diff:.2e}")
    assert max_diff < 1e-4, "traced graph diverges from eager model"

    scale = 1.0 / 255.0
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, datamod.IMG_SIZE, datamod.IMG_SIZE),
        scale=scale, bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )
    outputs = [ct.TensorType(name=n) for n in OUT_ORDER]

    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=outputs,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,
    )

    mlmodel.author = "Sylyo ML pipeline"
    mlmodel.short_description = (
        "Multi-task fashion model: clothing category, gender, season, usage, "
        "base colour, plus a 256-d embedding for wardrobe similarity search."
    )
    mlmodel.input_description["image"] = "RGB clothing photo (resized to 128x128)."
    for t in TASKS:
        mlmodel.output_description[t] = f"Softmax probabilities over {t} classes."
    mlmodel.output_description["embedding"] = "L2-normalized 256-d feature vector."
    mlmodel.user_defined_metadata["labels_json"] = json.dumps(labels)

    out_path = os.path.join(ART, "FashionMultiTask.mlpackage")
    mlmodel.save(out_path)
    with open(os.path.join(ART, "labels.json"), "w") as f:
        json.dump(labels, f, indent=2)
    print(f"Saved CoreML model -> {out_path}")

    # Structural validation of the saved spec (no runtime needed).
    spec = ct.utils.load_spec(out_path)
    print("\n=== CoreML spec ===")
    for inp in spec.description.input:
        kind = inp.type.WhichOneof("Type")
        print(f"  input  {inp.name}: {kind}")
    for outp in spec.description.output:
        print(f"  output {outp.name}: {outp.type.WhichOneof('Type')}")
    print("  label counts:", {k: len(v) for k, v in labels.items()})


if __name__ == "__main__":
    main()
