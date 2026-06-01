# A-cut Flutter Aesthetic Preprocessing Audit

## 1. Executive Summary
- **Active Aesthetic Models:** NIMA, RGNet, A-LAMP, and ICAA are currently active in the production ensemble.
- **Preprocessing Contracts:** **CONFIRMED**. Most models use RGB input with either `zeroToOne` (NIMA, RGNet) or `imageNet` (ICAA) normalization. A-LAMP uses a complex signature-based input with global and adaptive patches.
- **Tensor Sharing:** **PARTIAL**. NIMA correctly shares the 224x224 `zeroToOne` tensor with technical models (KonIQ/FLIVE). However, ICAA performs a redundant 224x224 resize because its normalization (`imageNet`) is different.
- **Top Bottlenecks:** 
    1. Main isolate image decoding.
    2. Main isolate A-LAMP adaptive patch selection and scoring.
    3. Redundant resizing for ICAA.
    4. Main isolate Float32 tensor conversion for all models.
- **Recommendation:** Proceed with offloading all preprocessing tasks to background isolates. Implement intermediate resize caching to allow ICAA to share the 224x224 resized image before normalization.

## 2. Files Inspected
- `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`: Model contracts and default weights.
- `lib/feature/a_cut/model/aesthetic_ensemble_weights.dart`: Enforced weights and normalization logic.
- `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`: Blending logic for the aesthetic ensemble.
- `lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart`: TFLite inference and model-specific preprocessing orchestrator.
- `lib/feature/a_cut/layer/inference/image_preprocessor.dart`: Core preprocessing logic including A-LAMP patch selection.
- `lib/config/experimental_features.dart`: Feature flags and debug settings.

## 3. Active Aesthetic Model Inventory
| Model ID | Asset Path | Metadata Path | Status | Weight | Output Scale |
|----------|------------|---------------|--------|--------|--------------|
| `nima_mobile` | `nima_mobile_fixed_preproc_fp16.tflite` | `nima_mobile_fixed_preproc.metadata.json` | Enabled | 0.10 | 1-10 (Dist) -> [0,1] |
| `rgnet_pil_resize_aadb` | `rgnet_pil_resize_aadb_fp16.tflite` | `rgnet_pil_resize_aadb.metadata.json` | Enabled | 0.40 | [0, 1] (Scalar) |
| `mobile_alamp_v2` | `mobile_alamp_v2_fp16.tflite` | `mobile_alamp_v2.metadata.json` | Enabled | 0.30 | [0, 1] (Scalar) |
| `icaa_color_aesthetic` | `icaa_dat_tf_native_fp16.tflite` | `icaa_dat_tf_native.metadata.json` | Enabled | 0.20 | [0, 1] (Scalar) |

## 4. Aesthetic Score Formula Audit
- **Exact Blending Logic:** `finalAestheticScore = (nima * 0.1) + (rgnet * 0.4) + (alamp * 0.3) + (icaa * 0.2)`
- **Source File:** `lib/feature/a_cut/model/aesthetic_ensemble_weights.dart` and `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`.
- **Decision:** **CONFIRMED**. The weights are explicitly defined and enforced in the code.

## 5. NIMA Preprocessing Contract
- **Input Shape:** `[1, 224, 224, 3]` (RGB)
- **Resize Method:** Stretch resize (img.Interpolation.linear).
- **Normalization:** `zeroToOne` (/255.0).
- **Output:** 10-bin distribution. Conversion uses weighted mean of bins (1-10) then shifts to [0, 1] range.

## 6. RGNet Preprocessing Contract
- **Input Shape:** `[1, 256, 256, 3]` (RGB)
- **Resize Method:** Stretch resize (img.Interpolation.linear).
- **Normalization:** `zeroToOne` (/255.0).
- **Output:** Scalar Unit Interval [0, 1].

## 7. A-LAMP Preprocessing Contract
- **Global Input:** `[1, 384, 384, 3]` using `resizeWithPad`.
- **Patch Input:** `[1, patchCount, 224, 224, 3]` (adaptive patches).
- **Selection:** `_selectAlampAdaptivePatchBoxes` uses a multi-scale grid search with scoring based on edges, luminance, and color variance.
- **Normalization:** `rawZeroTo255` (0.0 to 255.0).
- **Output:** Scalar Unit Interval [0, 1].

## 8. ICAA Preprocessing Contract
- **Input Shape:** `[1, 224, 224, 3]` (RGB)
- **Resize Method:** Stretch resize (img.Interpolation.linear).
- **Normalization:** `imageNet` (Mean: [0.485, 0.456, 0.406], Std: [0.229, 0.224, 0.225]).
- **Output:** Scalar Unit Interval [0, 1] at `outputIndex: 1`.

## 9. Legacy / Disabled / Debug-only Aesthetic Models
- **TOPIQ mixed112:** Present in contracts but has `weight: 0.0`. Used only for C6 candidate logging.
- **Experimental Flags:** `disableRgnetDuringBatchScoring` and `disableAlampDuringBatchScoring` exist in `ExperimentalFeatures` but are explicitly ignored in `TfliteAestheticService._isModelDisabledForBatch`, meaning these models currently run even in batch mode.

## 10. Shared Preprocessing Opportunities
- **Decoded Image:** Shared by all models via `AcutImagePreprocessBundle`. **SAFE**.
- **Resized Image:** NIMA, ICAA, and technical models share 224x224 target. Currently re-resized for ICAA. **SAFE to share intermediate resized img.Image**.
- **Normalized Tensor:** NIMA shares with KonIQ/FLIVE. **SAFE/ALREADY IMPLEMENTED**.

## 11. Full Aesthetic Scoring Flow
1. **Decode:** `ImagePreprocessor` decodes thumbnail into `img.Image` (Main Isolate).
2. **Technical Preproc:** KonIQ/FLIVE resize to 224x224 and normalize (Main Isolate).
3. **NIMA Preproc:** Reuses 224x224 normalized tensor from technical models.
4. **RGNet Preproc:** Resizes to 256x256 and normalizes (Main Isolate).
5. **ICAA Preproc:** Resizes to 224x224 and applies `imageNet` normalization (Main Isolate).
6. **A-LAMP Preproc:** Selects adaptive patches and generates global view tensor (Main Isolate).
7. **Inference:** TFLite runs each model sequentially.
8. **Blending:** Aesthetic ensemble weights applied.

## 12. Bottlenecks
1. **HIGH:** `img.decodeImage` on Main Isolate.
2. **HIGH:** `_selectAlampAdaptivePatchBoxes` (A-LAMP) scoring loop on Main Isolate.
3. **HIGH:** Multiple `img.copyResize` calls on Main Isolate.
4. **MEDIUM:** Redundant resize for ICAA (224x224).
5. **MEDIUM:** Normalization loops in Dart for all models.

## 13. Safe Optimization Plan
- **Optimization 1:** Offload `decodeImage` and all `AcutImagePreprocessBundle` tensor generation methods to background isolates using `compute`.
- **Optimization 2:** Cache the 224x224 resized `img.Image` in `AcutImagePreprocessBundle` so ICAA can skip the second `img.copyResize`.
- **Optimization 3:** Move the A-LAMP adaptive patch selection scoring logic to a background isolate.

## 14. Risky Optimizations to Avoid
- **Risky:** Changing A-LAMP patch selection algorithm or sampling density (12x12).
- **Risky:** Changing interpolation from `linear` for any model.

## 15. Recommended Next Action
**A. Aesthetic preprocessing is clear; prepare Codex prompt for safe speed optimization only.**

## 16. Codex Follow-up Prompt Draft
```text
Optimize Aesthetic Preprocessing via Isolates:
1. In `lib/feature/a_cut/layer/inference/image_preprocessor.dart`:
   - Wrap `img.decodeImage` in `createBundle` with `compute`.
   - Update `AcutImagePreprocessBundle` methods (`rgbFloat32`, `resizeWithPadRgbFloat32`, `alampAdaptivePatchesFloat32`) to run their core logic (resizing and loops) in background isolates.
   - Implement an internal cache for resized `img.Image` objects (e.g. `Map<String, img.Image> _resizedCache`) to avoid redundant `img.copyResize(224, 224)` for ICAA.
2. Ensure A-LAMP patch selection scoring (`_scorePatchCandidate`) is also moved to an isolate if possible, or ensured to run within the background task of `alampAdaptivePatchesFloat32`.
3. Verify that 224x224 models (NIMA, ICAA, KonIQ, FLIVE) reuse the same background-generated resized image where appropriate.
```
