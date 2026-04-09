# FastSCNN Native Migration Plan (MethodChannel + EventChannel)

## Goal
- Move FastSCNN inference from Flutter/Dart to native (Android/iOS).
- Keep Flutter responsible for UI and composition guidance only.
- Reduce camera jank while preserving real-time guidance behavior.

## Current Bottleneck
- Current flow in landscape mode:
  1. `YOLOViewController.captureFrame()` returns JPEG bytes.
  2. Dart decodes, resizes, normalizes image.
  3. Dart runs TFLite + argmax postprocess.
  4. Analyzer computes guidance.
- Heavy preprocessing/postprocessing on Flutter side causes frame drops.

## Target Architecture
- Flutter:
  - Calls native with frame bytes (or frame handle later).
  - Receives lightweight segmentation result and analyzer inputs.
  - Draws overlay and guidance text.
- Native:
  - Model load/init/dispose.
  - Input preprocessing (decode/resize/normalize).
  - TFLite inference.
  - Argmax/class map generation.
  - Optional perf/status events.

## Channel Contract (v1)
- MethodChannel: `pozy.fastscnn/method`
  - `initialize`: `{modelAssetPath, numThreads}` -> `{ok, inputWidth, inputHeight}`
  - `segment`: `{jpegBytes}` -> `{ok, width, height, classMapFlat}`
  - `dispose`: `{}` -> `{ok}`
- EventChannel: `pozy.fastscnn/event`
  - Emits status/perf:
    - `{type:"status", state:"initialized|running|disposed"}`
    - `{type:"perf", preprocessMs, inferenceMs, postprocessMs, totalMs}`
    - `{type:"error", message}`

## Rollout Plan
1. Add Dart bridge and fallback pipeline (done in this change).
2. Wire landscape screen to use pipeline (done in this change).
3. Implement Android native engine behind the same contract.
4. Implement iOS native engine (same contract).
5. Replace JPEG capture path with direct camera frame path if needed (v2 optimization).

## Safety Strategy
- If native channel is unavailable or fails, automatically fallback to existing Dart segmentor.
- UI behavior remains unchanged.
- Keep analyzer and overlay logic untouched for regression safety.

## Success Metrics
- Camera preview smoothness improves during landscape mode.
- Segmentation interval remains real-time for guidance.
- No feature regression in guidance/overlay.

## Notes
- This migration allows incremental adoption:
  - Today: fallback-capable integration.
  - Next: native backend activation without changing screen logic.
