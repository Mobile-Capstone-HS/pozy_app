# A-CUT RGNet Mobile

#### A-CUT Capstone Project — Mobile Image Quality and Aesthetic Assessment

> Mobile-adapted implementation of RGNet for aesthetic assessment.

## Introduction

Mobile-adapted implementation of RGNet for aesthetic assessment. This version was specifically adapted for the AADB dataset and optimized for mobile deployment.

- **Role**: A-CUT aesthetic ensemble model.
- **Task**: Image Quality and Aesthetic Assessment.

## Model / Method

Adapted RGNet model using a MobileNet-style backbone. A critical requirement for maintaining performance is the use of PIL Bilinear resize during preprocessing. It serves as a key component of the A-CUT aesthetic ensemble.

- **Artifacts**: Inferred from scripts

## Dataset and Benchmark

- Benchmark results are summarized below. See `docs/benchmark_summary.md` for detailed per-dataset analysis.
- Note: Large datasets are excluded due to size/license constraints.

## Model Weights / Artifacts

- Due to size constraints, artifacts larger than 50MB are not included in this repository.
- Recommended hosting: GitHub Releases.
- See `models/download.md`.

## Repository Structure

```
.
├── configs/
├── docs/
├── models/
├── results/
├── scripts/
└── requirements.txt
```

## Requirements

Please refer to `requirements.txt`. Minimal dependencies include `torch`, `tensorflow`, `numpy`, and `pillow`.

## Quick Start

```bash
pip install -r requirements.txt
python scripts/predict_rgnet.py --model_path models/model_files/rgnet_pil_resize_aadb_fp16.tflite --image_path test_images/sample.jpg
```
*(Verify path assumptions in `docs/reproduction_notes.md`)*

## Results

| Dataset | Metric | Value | Evidence Path | Decision |
|---------|--------|-------|---------------|----------|
| AADB | SRCC | 0.6819 | outputs/acut_capstone_final_report_20260526/model_metrics_summary.csv | Ensemble Component |
| AADB (TFLite FP16) | SRCC | 0.6647 | outputs/rgnet_v1_aadb_pil_resize_retrain_20260524_tflite/parity_report.md | Ensemble Component |
| AVA | Accuracy | 0.7697 | outputs/acut_capstone_final_report_20260526/model_metrics_summary.csv | Ensemble Component |

## Limitations

- Results are based on local reproduction and may not exactly match original papers.
- See `docs/model_card.md` for detailed limitations.

## Citation

```bibtex
@misc{acut_rgnet_2026,
  title        = {A-CUT RGNet Mobile: Mobile Image Quality and Aesthetic Assessment Model},
  author       = {Kim, Gwanjung},
  year         = {2026},
  note         = {Capstone project repository}
}
```
### Original References

- Liu et al., Composition-Aware Image Aesthetics Assessment, WACV 2020.

## Related Repositories

- [A-CUT Public Model Repositories](..)
