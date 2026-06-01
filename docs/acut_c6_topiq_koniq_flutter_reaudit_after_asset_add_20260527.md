# A-cut C6 TOPIQ+KonIQ Flutter Re-Audit After Asset Add

## 1. Summary
The TOPIQ mixed112 assets have been successfully added to the project. The architecture is mostly ready, but a minor extension to the `AestheticModelContract` and `TfliteAestheticService` is required to support the `resize_with_pad` strategy specified in the TOPIQ metadata. Once this is added, the project will be ready for log-only C6 scoring implementation.

## 2. Asset Confirmation
- **TFLite Model**: `assets/models/topiq_lite_mixed112_frozen_fp16.tflite` (12MB) - **Present**
- **Metadata JSON**: `assets/models/topiq_lite_mixed112.metadata.json` - **Present**
- **Pubspec Inclusion**: `pubspec.yaml` correctly bundles `assets/models/`.

## 3. Metadata Contract
- **Model ID**: `topiq_lite_mixed112`
- **Input Shape**: `[1, 384, 384, 3]`
- **DType**: `float32`
- **Resizing**: `resize_with_pad` (**Requires implementation support**)
- **Normalization**: `none` (Corresponds to `ImageNormalization.rawZeroTo255`)
- **Output Scale**: `raw_output * 100.0` (Corresponds to `AestheticModelOutputType.scalarPercent`)

## 4. Existing Inference Architecture
- **Contract**: `AestheticModelContract` handles metadata-driven resolution but lacks a resizing strategy field.
- **Service**: `TfliteAestheticService` handles sequential model execution. It currently defaults to standard resize (`rgbFloat32`).
- **Preprocessor**: `ImagePreprocessor` and `AcutImagePreprocessBundle` already implement `resizeWithPadRgbFloat32`, but it is not yet wired to the generic model runner.
- **Evaluation**: `OnDevicePhotoEvaluationService` orchestrates the technical models (KonIQ, FLIVE).

## 5. Required Future Code Changes
1. **Extend `AestheticModelContract`**: Add an `enum AestheticModelResizing { resize, resizeWithPad }` and a corresponding field to the contract class.
2. **Update `TfliteAestheticService`**: In `_runTensorContract`, check the resizing strategy and call `bundle?.resizeWithPadRgbFloat32` when required.
3. **Add TOPIQ Contract**: Define `topiqLiteMixed112Contract` in `aesthetic_model_contract.dart`.

## 6. C6 Log-Only Insertion Point
The log-only C6 score calculation should be placed in `OnDevicePhotoEvaluationService.evaluate` (`lib/feature/a_cut/layer/evaluation/photo_evaluation_service.dart`) after receiving the `technicalSummary`.

```dart
// C6 = min(0.7 * TOPIQ + 0.3 * KonIQ, KonIQ + 8)
final koniq = _detail(technicalSummary, 'koniq_mobile')?.rawScore;
final topiq = _detail(technicalSummary, 'topiq_lite_mixed112')?.rawScore;
if (koniq != null && topiq != null) {
  final c6 = math.min(0.7 * topiq + 0.3 * koniq, koniq + 8);
  debugPrint('[C6_AUDIT] image=$fileName c6=$c6 koniq=$koniq topiq=$topiq');
}
```

## 7. Runtime Benchmark Plan
- **Preprocess Latency**: Compare `resizeWithPad` vs standard `resize` for 384x384.
- **Inference Latency**: Monitor `topiq_lite_mixed112` inference time on Galaxy S23 Ultra (expected ~120ms).
- **Memory Pressure**: Ensure sequential execution of KonIQ (224) and TOPIQ (384) does not trigger OOM during batch processing of 12 images.

## 8. Blockers
- **Resizing Strategy Support**: The generic `TfliteAestheticService` does not yet support switching to `resize_with_pad` based on contract/metadata. This is the only remaining technical blocker.
- **Asset Naming Mismatch**: Metadata recommends `topiq_lite_mixed112_fp16.tflite` but file is named `topiq_lite_mixed112_frozen_fp16.tflite`. The contract must use the actual filename.

## 9. Recommendation
**C. Need preprocessing support first**

The project is almost ready. The next step is to update the `AestheticModelContract` and `TfliteAestheticService` to support the `resize_with_pad` strategy. Once that is done, the TOPIQ model can be fully integrated for log-only C6 benchmarking.
