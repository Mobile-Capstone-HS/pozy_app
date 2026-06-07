# A-CUT NIMA Mobile

#### A-CUT Capstone Project — Mobile Image Quality and Aesthetic Assessment

> Mobile-optimized implementation of NIMA (Neural Image Assessment) predicting aesthetic distribution.

## Introduction

Mobile-optimized implementation of NIMA (Neural Image Assessment) predicting aesthetic distribution. It was adapted and optimized for on-device performance in the A-CUT project.

- **Role**: A-CUT aesthetic ensemble model.
- **Task**: Image Quality and Aesthetic Assessment.

## Model / Method

Based on MobileNetV2 architecture fine-tuned on the AVA dataset. The final version includes a critical fix for a double-preprocessing bug in the EfficientNetV2-based training pipeline, significantly improving ranking performance.

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
python scripts/predict_nima.py --model_path models/model_files/nima_mobile_fixed_preproc_fp16.tflite --image_path test_images/sample.jpg
```
*(Verify path assumptions in `docs/reproduction_notes.md`)*

## Results

| Dataset | Metric | Value | Evidence Path | Decision |
|---------|--------|-------|---------------|----------|
| AVA | SRCC | 0.5894 | outputs/nima_fixed_preproc_eval_20260525/report.md | Ensemble Component |
| AVA | PLCC | 0.5929 | outputs/nima_fixed_preproc_eval_20260525/report.md | Ensemble Component |
| AVA | AUC | 0.8018 | outputs/nima_fixed_preproc_eval_20260525/report.md | Ensemble Component |

## Limitations

- Results are based on local reproduction and may not exactly match original papers.
- See `docs/model_card.md` for detailed limitations.

## Citation

```bibtex
@misc{acut_nima_2026,
  title        = {A-CUT NIMA Mobile: Mobile Image Quality and Aesthetic Assessment Model},
  author       = {Kim, Gwanjung},
  year         = {2026},
  note         = {Capstone project repository}
}
```
### Original References

- Talebi, H., & Milanfar, P. (2018). NIMA: Neural Image Assessment. IEEE Transactions on Image Processing, 27(8), 3998-4011.

## Related Repositories

- [A-CUT Public Model Repositories](..)
