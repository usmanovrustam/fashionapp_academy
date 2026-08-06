# Nook ML — standalone model package

Self-contained folder with Nook's on-device Core ML models, the scripts to
regenerate them, and a local tester. Copy it anywhere (e.g. your Desktop):

```bash
cp -r nook-ml ~/Desktop/nook-ml
cd ~/Desktop/nook-ml
```

## Setup (once) — to run the cutout tester

Works on any recent Python (incl. 3.13). On macOS use plain PyPI:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

`run_cutout.py` needs only `torch`, `numpy`, `scipy`, `pillow`,
`huggingface_hub` — no coremltools/torchvision.

## Setup — to regenerate the Core ML models (optional)

`coremltools` requires **Python ≤ 3.12**. If you're on 3.13+, make a 3.12 venv:

```bash
python3.12 -m venv .venv-export && source .venv-export/bin/activate
pip install --index-url https://download.pytorch.org/whl/cpu torch==2.5.1 torchvision==0.20.1
pip install -r requirements-export.txt
```

## Contents

```
nook-ml/
  segmentation/
    u2net.mlpackage        ← shipped cutout model (u2netp saliency)
    u2net_arch.py          ← U^2-Net architecture (Apache-2.0)
    u2net_common.py        ← loads pretrained u2netp weights
    export_coreml.py       ← regenerate u2net.mlpackage
    run_cutout.py          ← test the cutout on ANY photo
  classifier/
    FashionMultiTask.mlpackage  ← category/attributes/embedding model
    labels.json                 ← class labels
    taxonomy.py, data.py, model.py, train.py,
    export_coreml.py, eval_similarity.py  ← training pipeline
  requirements.txt
```

## Test the cutout on your own photo (useful for debugging)

```bash
cd segmentation
python run_cutout.py /path/to/dress.jpg
```

It writes next to the input:
- `*_mask.png` raw saliency mask
- `*_clean.png` cleaned mask (largest component + filled holes)
- `*_square.jpg` centered square crop
- `*_cutout.png` transparent cutout (what the app shows)

This is the exact on-device logic, so you can see whether something like a
pleated petticoat is part of the garment (kept) vs. background.

## Regenerate the models

```bash
cd segmentation && python export_coreml.py       # -> u2net.mlpackage
cd ../classifier && python train.py --epochs 60  # -> artifacts/checkpoint.pt
                    python export_coreml.py       # -> artifacts/FashionMultiTask.mlpackage
```

## Use in the iOS app

The models live in the app at `fashionapp/u2net.mlpackage` and (on the
classifier branch) `fashionapp/FashionMultiTask.mlpackage`. The `fashionapp/`
folder is a synchronized Xcode group, so replacing those packages and rebuilding
is all that's needed — no `project.pbxproj` edits.

> Note: CoreML **inference** and the iOS build require macOS + Xcode. The Python
> scripts (train/export/run_cutout) run anywhere; run_cutout uses PyTorch for the
> mask, matching the exported CoreML model.
