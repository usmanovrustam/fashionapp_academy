"""Export U2NETP to CoreML for on-device background removal.

Input : RGB image 320x320, pixels 0-255 (CoreML ImageType; ÷255 + ImageNet
        normalization baked into the graph).
Output: single-channel foreground mask 'mask' (1x1x320x320, 0-1).

Replaces the previous weightless fashionapp/u2net.mlpackage.
"""
from __future__ import annotations

import os
import shutil

import torch
import coremltools as ct

from u2net_common import SIZE, load_u2netp, SegExport

ART = os.path.join(os.path.dirname(__file__), "artifacts")
APP = os.path.join(os.path.dirname(__file__), "..", "fashionapp")


def main():
    export = SegExport(load_u2netp()).eval()
    example = torch.rand(1, 3, SIZE, SIZE)

    with torch.no_grad():
        eager = export(example)
    traced = torch.jit.trace(export, example)
    with torch.no_grad():
        tr = traced(example)
    max_diff = float((eager - tr).abs().max())
    print(f"Torch eager-vs-traced max diff: {max_diff:.2e}")
    assert max_diff < 1e-4

    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, SIZE, SIZE),
                             scale=1.0 / 255.0, bias=[0.0, 0.0, 0.0],
                             color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="mask")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.author = "Sylyo ML pipeline"
    mlmodel.short_description = "U2NETP foreground/background segmentation for clothing cutouts."
    mlmodel.input_description["image"] = "RGB photo (resized to 320x320)."
    mlmodel.output_description["mask"] = "Foreground probability mask (0-1), 320x320."

    art_path = os.path.join(ART, "u2netp.mlpackage")
    mlmodel.save(art_path)
    app_path = os.path.join(APP, "u2net.mlpackage")
    if os.path.exists(app_path):
        shutil.rmtree(app_path)
    shutil.copytree(art_path, app_path)
    print(f"Saved {art_path}\nReplaced {app_path}")

    spec = ct.utils.load_spec(app_path)
    print("\n=== CoreML spec ===")
    for inp in spec.description.input:
        print(f"  input  {inp.name}: {inp.type.WhichOneof('Type')}")
    for outp in spec.description.output:
        print(f"  output {outp.name}: {outp.type.WhichOneof('Type')}")


if __name__ == "__main__":
    main()
