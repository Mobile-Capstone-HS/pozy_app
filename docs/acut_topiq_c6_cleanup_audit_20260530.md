# A-cut TOPIQ/C6 Cleanup Audit

## 1. Executive Summary
Cleanup of TOPIQ/C6 artifacts is **SAFE** to proceed. TOPIQ was a candidate for technical quality scoring (C6) that has been retired in favor of the existing KonIQ + FLIVE ensemble. All TOPIQ-specific code is currently gated by experimental flags or used only for diagnostic logging. Removing these artifacts will reduce the app bundle size by ~12.6 MB and simplify the inference layer without affecting production scoring or UI behavior.

## 2. Current Branch and Git Status
- **Branch:** `feat/acut`
- **Status:** Ahead of `origin/feat/acut` by 29 commits.
- **Uncommitted Changes:** Several files in `lib/feature/a_cut/` are modified (likely from previous aesthetic timing/parity tasks).
- **Untracked Files:** Includes TOPIQ-related logs and scripts.

## 3. Files Inspected
- `lib/config/experimental_features.dart`: Gating flags for C6 and TOPIQ debug.
- `lib/feature/a_cut/layer/evaluation/photo_evaluation_service.dart`: Implementation of C6 candidate logging.
- `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`: Definition of TOPIQ model contract.
- `lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart`: TOPIQ-specific logging and stats logic.
- `lib/feature/a_cut/layer/inference/image_preprocessor.dart`: Shared `resizeWithPad` logic (Must Keep).
- `pubspec.yaml`: Asset directory registration.

## 4. TOPIQ/C6 Reference Inventory

| File | Symbol/Reference | Classification | Safe Action |
|------|------------------|----------------|-------------|
| `experimental_features.dart` | `enableC6TopiqKoniqCandidate` | experiment-only | Remove |
| `experimental_features.dart` | `enableTopiqPreprocessDebug` | debug-only | Remove |
| `experimental_features.dart` | `enableTopiqTensorFingerprint` | debug-only | Remove |
| `aesthetic_model_contract.dart` | `topiqLiteMixed112Contract` | experiment-only | Remove |
| `photo_evaluation_service.dart` | `_logC6TopiqCandidate` | debug-only | Remove |
| `tflite_aesthetic_service.dart` | `_maybeLogTopiqPreprocessDebug` | debug-only | Remove |
| `tflite_aesthetic_service.dart` | `_maybeLogTopiqTensorFingerprint` | debug-only | Remove |
| `tflite_aesthetic_service.dart` | `_calculateTopiqTensorStats` | debug-only | Remove |
| `tflite_aesthetic_service.dart` | `_TopiqTensorStats` | debug-only | Remove |

## 5. Asset and Metadata Cleanup

| Asset Path | Tracked | Recommended Action |
|------------|---------|--------------------|
| `assets/models/topiq_lite_mixed112_frozen_fp16.tflite` | Yes | Delete (12.6 MB) |
| `assets/models/topiq_lite_mixed112.metadata.json` | Yes | Delete |
| `pubspec.yaml` | Yes | **KEEP** (registers entire directory) |

## 6. Code Cleanup Plan

### Safe Removals
- All constants and methods identified in Section 4.
- Logic in `tflite_aesthetic_service.dart` that specifically checks for `topiq_lite_mixed112` ID.
- Call to `_logC6TopiqCandidate` in `photo_evaluation_service.dart`.

### Risky Removals
- **None identified.** All TOPIQ code is strictly decoupled from the production path.

### Unclear References
- **None.** Classification is clear for all found references.

## 7. Must Keep
- **KonIQ/FLIVE Models:** These remain the production technical scoring models.
- **Production Weights:** The 0.6 / 0.4 weights (or future 4/7 : 3/7) for technical scoring.
- **Shared Preprocessing:** `AestheticModelResizeMode.resizeWithPad`, `preprocessResizeWithPadToRgbFloat32`, and the logic in `image_preprocessor.dart` must remain as they are used by (or intended for) A-LAMP and other models.
- **General Debug Tools:** `AcutAestheticTimingDebug` and `AcutAestheticParityDebug` must remain as they support the active aesthetic model optimization phase.

## 8. Validation Plan
1. `flutter pub get`: Ensure no asset registration issues.
2. `flutter analyze`: Verify no broken references or missing imports.
3. `flutter test`: Run available unit tests to ensure no regressions.
4. Verify `technical_score` logs still show KonIQ and FLIVE contributions.

## 9. Recommended Next Action
**A. Safe to proceed with Codex cleanup**
The scope is well-defined and removal is low-risk.

## 10. Codex Follow-up Prompt Draft
```text
Remove retired TOPIQ/C6 technical quality candidate:
1. Delete assets/models/topiq_lite_mixed112_frozen_fp16.tflite
2. Delete assets/models/topiq_lite_mixed112.metadata.json
3. In lib/config/experimental_features.dart, remove:
   - enableC6TopiqKoniqCandidate
   - enableTopiqPreprocessDebug
   - enableTopiqTensorFingerprint
4. In lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart, remove topiqLiteMixed112Contract.
5. In lib/feature/a_cut/layer/evaluation/photo_evaluation_service.dart, remove _logC6TopiqCandidate and its call site.
6. In lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart, remove:
   - _maybeLogTopiqPreprocessDebug
   - _maybeLogTopiqTensorFingerprint
   - _calculateTopiqTensorStats
   - _calculateTopiqPatchMean
   - _TopiqTensorStats class
   - Any calls or special logic for 'topiq_lite_mixed112'.
7. Delete related docs and logs:
   - docs/acut_c6_topiq_koniq_*
   - docs/acut_topiq_tensor_fingerprint_*
   - scripts/parse_topiq_logs.py
   - c6_*.log files in root
```
