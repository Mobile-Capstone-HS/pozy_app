# RGNet PIL-Resize Retrain TFLite Parity Report

## 1. Summary
Exported the RGNet model retrained with PIL/mobile-like resize to TFLite FP32 and FP16.
Verified parity and benchmarked on the AADB test set.

## 2. Export Source
- Weights: `outputs/rgnet_v1_aadb_pil_resize_retrain_20260524/best.weights.h5`
- Reconstructed from `src.models.rgnet_paper_v1.build_rgnet_paper_v1_model`

## 3. Generated Files
- `rgnet_pil_resize_aadb_fp32.tflite`
- `rgnet_pil_resize_aadb_fp16.tflite`
- `export_metadata.json`
- `aadb_mobile_like_eval_summary.json`
- `aadb_mobile_like_predictions.csv`

## 4. Keras vs TFLite Parity (AADB Test)
| Model | Max Abs Diff | Mean Abs Diff | Pearson | Spearman |
| :--- | :--- | :--- | :--- | :--- |
| FP32 | 0.000329 | 0.000059 | 1.000000 | N/A |
| FP16 | 0.001068 | 0.000157 | 0.999999 | 0.999997 |

## 5. AADB Mobile-Like Benchmark
| Model | SRCC | PLCC | MAE | RMSE |
| :--- | :--- | :--- | :--- | :--- |
| Keras (Best Weights) | 0.6648 | 0.6708 | 0.1219 | 0.1522 |
| TFLite FP32 | 0.6648 | 0.6708 | 0.1219 | 0.1522 |
| TFLite FP16 | 0.6647 | 0.6708 | 0.1219 | 0.1522 |

## 6. Comparison with Old Deployed RGNet
- Old Deployed TFLite (FP16): SRCC **0.6139**
- New TFLite (FP16): SRCC **0.6647**
- Improvement: **0.0508**

## 7. Deployment Decision
**DEPLOY**
The new model recovers the resize gap and significantly improves ranking performance on mobile-like preprocessing.

## 8. Limitations
- Benchmark on AADB test only.
- Parity evaluated on 1,000 samples.

## 9. Exact Flutter Copy Command
```bash
cp outputs/rgnet_v1_aadb_pil_resize_retrain_20260524_tflite/rgnet_pil_resize_aadb_fp16.tflite assets/models/rgnet_paper_aadb_fp16.tflite
```
