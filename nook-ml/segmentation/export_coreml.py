"""Export the u2netp segmentation model to CoreML (standalone).

  python export_coreml.py            # -> ./u2net.mlpackage

Input : RGB image 320x320 (0-255; ÷255 + ImageNet norm baked in).
Output: single 0-1 foreground 'mask'.
"""
import os
import torch
import coremltools as ct
from u2net_common import SIZE, load_u2netp, SegExport

OUT = os.path.join(os.path.dirname(__file__), "u2net.mlpackage")


def main():
    export = SegExport(load_u2netp()).eval()
    example = torch.rand(1, 3, SIZE, SIZE)
    traced = torch.jit.trace(export, example)

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
    mlmodel.short_description = "u2netp foreground/background segmentation for clothing cutouts."
    mlmodel.save(OUT)
    print(f"saved {OUT}")


if __name__ == "__main__":
    main()
