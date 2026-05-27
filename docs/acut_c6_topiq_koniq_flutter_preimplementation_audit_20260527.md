# A-cut C6 TOPIQ+KonIQ Flutter Pre-Implementation Audit

## 1. Executive Summary
Simultaneous execution of TOPIQ mixed112 and KonIQ mobile in the Flutter app is architecturally feasible using the existing `TfliteAestheticService` and `AestheticModelContract` framework. However, the **TOPIQ mixed112 model and its metadata are currently missing** from the project assets. Existing logs in `outputs/` suggest a previous experimental run, but the current codebase does not include the necessary components for TOPIQ. 

Once the TOPIQ model is added, the C6 candidate score can be implemented as a log-only metric within the `OnDevicePhotoEvaluationService` without disrupting the production scoring path.

## 2. Asset Availability

| Asset | Path | Status |
| --- | --- | --- |
| KonIQ mobile TFLite | `assets/models/koniq_mobile.tflite` | **Present** |
| KonIQ mobile Metadata | `assets/models/koniq_mobile.metadata.json` | **Present** |
| FLIVE image TFLite | `assets/models/flive_image_mobile.tflite` | **Present** |
| FLIVE image Metadata | `assets/models/flive_image_mobile.metadata.json` | **Present** |
| TOPIQ mixed112 TFLite | `assets/models/topiq_mixed112.tflite` | **MISSING** |
| TOPIQ mixed112 Metadata | `assets/models/topiq_mixed112.metadata.json` | **MISSING** |

## 3. Pubspec Asset Inclusion
The `pubspec.yaml` file includes the entire `assets/models/` directory:
```yaml
  assets:
    - assets/models/
```
Any new model files added to this directory will be automatically bundled in the Flutter application.

## 4. Existing Runner Architecture
- **Model Definition**: `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart` defines `AestheticModelContract` for each model. KonIQ and FLIVE are already defined here.
- **Inference Service**: `lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart` (`TfliteAestheticService`) handles the execution of TFLite models sequentially.
- **Interpreter Management**: `lib/feature/a_cut/layer/inference/tflite_interpreter_manager.dart` manages the lifecycle and caching of `Interpreter` instances.
- **Evaluation Orchestration**: `lib/feature/a_cut/layer/evaluation/photo_evaluation_service.dart` (`OnDevicePhotoEvaluationService`) coordinates technical and aesthetic evaluations.

## 5. Preprocessing and Score Scale

| Model | Input Shape | Normalization | Output Type |
| --- | --- | --- | --- |
| **KonIQ mobile** | [1, 224, 224, 3] | 0..1 (div 255) | Scalar (0-100) |
| **FLIVE image** | [1, 224, 224, 3] | 0..1 (div 255) | Scalar (0-100) |
| **TOPIQ mixed112** | [1, 384, 384, 3]* | 0..255 (none)* | Scalar (0.0-1.0)* |

*\*Based on `outputs/topiq_mixed112_runtime_raw.log` findings.*

## 6. Sequential Execution Feasibility
- **Latency**: TOPIQ mixed112 inference takes ~100-140ms on Android. Adding it to the technical evaluation path will increase per-image latency by this amount.
- **Memory**: Each interpreter is cached. A 384x384 float32 input buffer requires ~1.7MB. Multiple models running sequentially on the same resized image is efficient if they share the same input resolution, but TOPIQ (384) differs from KonIQ/FLIVE (224), requiring a second resize operation.
- **Isolates**: The current implementation uses `compute()` (Flutter isolates) for preprocessing but inference runs on the main thread (managed by the TFLite plugin's own thread pool). Sequential execution will not cause UI jank if handled correctly in the evaluation service.

## 7. Candidate C6 Formula Placement
The safest insertion point for the log-only candidate score is in `OnDevicePhotoEvaluationService.evaluate` within `lib/feature/a_cut/layer/evaluation/photo_evaluation_service.dart`.

```dart
// Future implementation sketch
final koniq = technicalSummary.scoreDetails.firstWhere((d) => d.id == 'koniq_mobile').normalizedScore * 100;
final topiq = technicalSummary.scoreDetails.firstWhere((d) => d.id == 'topiq_mixed112').normalizedScore * 100;
final candidateC6 = math.min(0.7 * topiq + 0.3 * koniq, koniq + 8);
debugPrint('[C6_AUDIT] image=$fileName koniq=$koniq topiq=$topiq c6=$candidateC6');
```

## 8. Android Benchmark Requirements
Before full deployment, the following metrics must be collected on a Galaxy S23 Ultra:
- **Cold/Warm Load Time**: Time to initialize TOPIQ interpreter.
- **Inference Latency**: Distribution of inference time across 50+ images.
- **Batch Performance**: Total time for 12-image batch (KonIQ + FLIVE + TOPIQ).
- **Parity Check**: Validate that Flutter output matches WSL benchmark output within $10^{-5}$ tolerance.

## 9. Blockers
1. **Missing Assets**: `topiq_mixed112.tflite` and its metadata are not in the repository.
2. **Missing Contract**: TOPIQ mixed112 is not defined in `aesthetic_model_contract.dart`.
3. **Preprocessing Uncertainty**: While logs suggest 384x384 with 0..255 range, this must be verified against the official TOPIQ mixed112 TFLite export.

## 10. Recommendation
**B. Need TOPIQ asset/runner first**

The current codebase is prepared for multi-model technical scoring, but cannot proceed with C6 implementation until the TOPIQ mixed112 model is integrated into the `assets/models/` directory and defined in the inference layer.
