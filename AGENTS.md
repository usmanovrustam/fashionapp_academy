# AGENTS

## Cursor Cloud specific instructions

### Scanner ML cutout + live process UI

- On-device scan pipeline (`DefaultClothingScanPipeline`) emits **real** `ScanPipelineProgress` (stage + fraction + intermediate preview bytes). The scanner overlay (`MLProcessOverlay`) is driven by those updates — not a looping decorative animation.
- Stages shown in UI: detect → segment → isolate → cutout → metadata. `persistAssets` runs later on save, not during the analyzing overlay.
- Cutout cleanliness: `ImageProcessing.cleanedMask` does stricter binarize (140), morphological open, largest component, hole fill, sparse edge-strip trim, and a light erode. `applyMask` uses nearest-neighbor + hard alpha (≥128 → 255) so soft side halos do not appear.
- **Person removal cutout formula** (SegFormer available): `mask = (u2net − body) ∩ garment`, then subtract dilated body again. `body` = Face/Hair/arms/legs from SegFormer. Never use plain u2net alone on worn photos — it keeps the whole human. Flat-lays have empty body → u2net ∩ garment (or u2net).
- Offline parity: `nook-ml/segmentation/run_cutout.py` mirrors the same cleanup. Use it on a Mac to validate photos without Xcode.
- Cloud agents cannot run Xcode/Swift here. After cutout/UI changes, validate mask logic with the Python cutout script (or unit checks on a saved mask) and remind the user to clean DerivedData + **re-scan** (old wardrobe cutouts stay stale).

### Standard commands

- App: open `fashionapp.xcodeproj` on macOS; see repo README / `nook-ml/README.md` for ML package usage.
- Firebase rules tests: under `scripts/` / emulator docs in the repo README when present.
