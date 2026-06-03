# A-Cut Aesthetic Ensemble V2 Implementation (2026-06-03)

## Files Changed
- `lib/feature/a_cut/model/aesthetic_ensemble_weights.dart`: Updated default weights.
- `lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart`: Excluded ICAA from active ensemble.
- `lib/feature/a_cut/model/aesthetic_ensemble_score_result.dart`: Updated `hasCompleteScores` logic.
- `lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`: Implemented calibration and updated aggregation.

## Final Formula
`aestheticScore1To10 = 0.37 * nimaCalib + 0.41 * rgnetCalib + 0.22 * alampCalib`
`finalScoreNormalized = ((aestheticScore1To10 - 1.0) / 9.0).clamp(0.0, 1.0)`

## Calibration Constants
- **NIMA:** slope 0.8126, intercept 1.4492
- **RGNet:** slope 0.0899, intercept 4.8656
- **A-LAMP:** slope 0.1637, intercept 4.6493

## Scale Mapping (Normalized -> Raw 1..10)
- **NIMA:** `raw10 = norm * 9.0 + 1.0`
- **RGNet:** `raw10 = norm * 10.0`
- **A-LAMP:** `raw10 = norm * 10.0`

## ICAA Exclusion
ICAA is assigned a weight of `0.00` and removed from `activeAestheticEnsembleContracts`. It is no longer executed in production A-cut scoring but the contract and assets are preserved.

## Validation Commands
- `dart format lib/feature/a_cut/model/aesthetic_ensemble_weights.dart lib/feature/a_cut/layer/inference/aesthetic_model_contract.dart lib/feature/a_cut/model/aesthetic_ensemble_score_result.dart lib/feature/a_cut/layer/evaluation/aesthetic_ensemble_scoring_service.dart`
- `flutter analyze lib/feature/a_cut/`

## Remaining Parity Test Requirement
Empirical verification against the WSL benchmark is recommended to ensure the Dart implementation exactly matches the Python/WSL prototype outputs.
