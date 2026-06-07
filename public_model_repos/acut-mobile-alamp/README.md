# A-CUT Mobile A-LAMP

#### A-CUT Capstone Project — Mobile Image Quality and Aesthetic Assessment

> Mobile-optimized Multi-Patch aesthetic model inspired by A-LAMP.

## Introduction

Mobile-optimized Multi-Patch aesthetic model inspired by A-LAMP. This implementation provides a practical mobile multi-patch approach without the heavy graph object detection of the original paper.

- **Role**: A-CUT aesthetic ensemble model.
- **Task**: Image Quality and Aesthetic Assessment.

## Model / Method

Uses a MobileNetV3-Small backbone with a multi-patch selection and attention mechanism. It approximates the A-LAMP approach for mobile efficiency, achieving high accuracy on the AVA dataset.

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
python scripts/predict_quality_bundle.py --model_path models/model_files/mobile_alamp_v2_fp16.tflite --image_path test_images/sample.jpg
```
*(Verify path assumptions in `docs/reproduction_notes.md`)*

## Results

| Dataset | Metric | Value | Evidence Path | Decision |
|---------|--------|-------|---------------|----------|
| AVA | Accuracy | 0.7633 | outputs/acut_capstone_final_report_20260526/model_metrics_summary.csv | Ensemble Component |
| AVA | ROC-AUC | 0.7877 | outputs/acut_capstone_final_report_20260526/model_metrics_summary.csv | Ensemble Component |
| AVA (Mobile v2) | Val Accuracy | 0.7142 | outputs/mobile_alamp_v2_full_ava_20260519/report.md | Ensemble Component |

## Limitations

- Results are based on local reproduction and may not exactly match original papers.
- See `docs/model_card.md` for detailed limitations.

## Citation

```bibtex
@misc{acut_alamp_2026,
  title        = {A-CUT Mobile A-LAMP: Mobile Image Quality and Aesthetic Assessment Model},
  author       = {Kim, Gwanjung},
  year         = {2026},
  note         = {Capstone project repository}
}
```
### Original References

- Ma, S., Liu, J., & Chen, C. W. (2017). A-LAMP: Adaptive Layout-Aware Multi-Patch Deep Network for Photo Aesthetic Assessment. CVPR.

## Related Repositories

- [A-CUT Public Model Repositories](..)
