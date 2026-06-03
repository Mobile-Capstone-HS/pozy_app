# A-Cut Aesthetic Ensemble V2 Audit (2026-06-03)

## 1. Git Status Summary
* **Branch:** `main`
* **Current Local Changes:**
  * `lib/config/experimental_features.dart` (modified)
  * `lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart` (modified)
  * `lib/feature/a_cut/layer/scoring/image_scoring_service.dart` (modified)

## 2. Candidate Files Inspected
* `lib/feature/a_cut/model/aesthetic_ensemble_weights.dart`
* `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`
* `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`
* `lib/feature/a_cut/model/aesthetic_ensemble_score_result.dart`
* `lib/config/experimental_features.dart`
* `lib/feature/a_cut/layer/inference/tflite_aesthetic_service.dart`

## 3. NIMA Score Origin
* **Contract:** `nimaMobileContract` in `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`.
* **Execution:** `AestheticEnsembleScoringService.evaluate` invokes `_modelRunner.evaluateSingleModel` and extracts `runs[nimaMobileContract.id]?.detail.normalizedScore`.

## 4. RGNet Score Origin
* **Contract:** `rgnetPilResizeAadbContract` in `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`.
* **Execution:** `AestheticEnsembleScoringService.evaluate` extracts `runs[rgnetPilResizeAadbContract.id]?.detail.normalizedScore`.

## 5. A-LAMP Score Origin
* **Contract:** `mobileAlampV2Contract` in `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`.
* **Execution:** `AestheticEnsembleScoringService.evaluate` extracts `runs[mobileAlampV2Contract.id]?.detail.normalizedScore`.

## 6. ICAA Score Origin
* **Contract:** `icaaColorAestheticContract` in `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`.
* **Execution:** `AestheticEnsembleScoringService.evaluate` extracts `runs[icaaColorAestheticContract.id]?.detail.normalizedScore`.

## 7. Current Aesthetic Ensemble Calculation
* **File:** `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`
* **Class:** `AestheticEnsembleScoringService`
* **Logic:** Computes a weighted average of the `normalizedScore` properties directly (`scoreSum += modelScore * normalizedWeight`), with no slope/intercept calibration applied currently.

## 8. Current Formula and Weights
* **Formula:** Uncalibrated weighted sum bounded between [0.0, 1.0].
* **Weights:** Defined in `AestheticEnsembleWeights.defaults`:
  * NIMA: 0.10
  * RGNet: 0.40
  * A-LAMP: 0.30
  * ICAA: 0.20

## 9. Current Score Scales
* **NIMA:** Output is a distribution. Weighted mean is computed, mapped from `[1.0, 10.0]` to `[0.0, 1.0]` using `((rawScore - 1.0) / 9.0).clamp(0.0, 1.0)`.
* **RGNet:** Output is a Scalar Unit Interval mapped via `rawScore.clamp(0.0, 1.0)`.
* **A-LAMP:** Output is a Scalar Unit Interval mapped via `rawScore.clamp(0.0, 1.0)`.
* **ICAA:** Output is a Scalar Unit Interval (index 1) mapped via `rawScore.clamp(0.0, 1.0)`.

## 10. ICAA in Production Holistic Score?
**Yes.** `AestheticEnsembleWeights` currently assigns it a default weight of 0.20, making it an active component of the production score.

## 11. ICAA Executed in Production Scoring?
**Yes.** `activeAestheticEnsembleContracts` includes `icaaColorAestheticContract`. Note: It can be conditionally disabled via the `POZY_ACUT_SKIP_ICAA_EXPERIMENT` flag (`disableIcaaDuringBatchScoring`) during batch execution.

## 12. Minimal Safe Implementation Plan for Step 2
1. **Update Weights:** Change `AestheticEnsembleWeights.defaults` to NIMA: 0.37, RGNet: 0.41, A-LAMP: 0.22, ICAA: 0.00.
2. **Implement Calibration Formula:** In `AestheticEnsembleScoringService`, apply `raw_scaled_1_10 * slope + intercept` to each `normalizedScore` (e.g. by reversing normalization or explicitly rescaling to [1, 10] before calibration) before the weighted average.
3. **Disable ICAA Execution:** Remove `icaaColorAestheticContract` from the `activeAestheticEnsembleContracts` list in `aesthetic_model_contract.dart` so it is not run during A-cut inferences.
4. **Update Result Object:** In `AestheticEnsembleScoreResult.hasCompleteScores`, remove the `icaaScore != null` requirement so that degradation is not logged when ICAA is skipped. 

## 13. Files Likely to Change in Step 2
* `lib/feature/a_cut/model/aesthetic_ensemble_weights.dart`
* `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`
* `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`
* `lib/feature/a_cut/model/aesthetic_ensemble_score_result.dart`

## 14. Risks and Unknowns
* **Formula Mapping Interpretation:** The `raw_scaled_1_10` variable in the target formula requires clear implementation—whether it equates to `normalizedScore * 10` for RGNet/A-LAMP, or if it maps precisely to `[1, 10]`.
* **UI Dependencies:** `single_photo_eval_screen.dart` contains hardcoded label references (`"NIMA, ICAA, A-Lamp, RGNet"`). As UI changes are restricted, these labels may remain, but they are built to safely handle a `null` `icaaScore`.

## 15. Recommendation
**READY_FOR_STEP_2_IMPLEMENTATION**
