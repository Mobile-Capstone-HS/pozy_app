# A-cut C6 TOPIQ+KonIQ Android Smoke Report

## 1. Summary
The Android smoke test for A-cut C6 TOPIQ+KonIQ log-only scoring was successful. A total of 28 TOPIQ inferences were recorded across multiple sessions. Latency is well within acceptable limits for a technical scoring model (~112ms), and the C6 candidate score formula is correctly applied in the logs. No score validity issues (NaN, negative, or out-of-bounds) were found.

## 2. Runtime Statistics
| Metric | Count | Min (ms) | Mean (ms) | Median (ms) | Max (ms) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| TOPIQ Preprocess (384) | 28 | 8 | 16.07 | 13.0 | 64 |
| TOPIQ Inference Only | 28 | 99 | 112.04 | 108.0 | 212 |
| TOPIQ Total Additional | 28 | 111 | 129.93 | 121.0 | 287 |

*Note: Max values likely reflect cold-start or first-inference overhead (model loading/initialization).*

## 3. Score Validity
- **Range Check (0-100)**: PASS (All scores are between 33.09 and 79.10)
- **Non-Numeric Check**: PASS (No NaN or Infinity values found)
- **Consistency**: PASS (Duplicate images show identical scores across different sessions)

## 4. C6 Formula Check
The C6 candidate formula `min(0.7 * TOPIQ + 0.3 * KonIQ, KonIQ + 8)` was verified against all 28 log entries.
- **Formula Accuracy**: 100% (All entries match the expected calculation within 0.01 precision)
- **Cap Behavior**: PASS (Candidate score never exceeds `KonIQ + 8` or `0.7*TOPIQ + 0.3*KonIQ`)

## 5. Delta Analysis
Delta is defined as `candidate_c6_score - existing_technical_score_100`.

### Top 5 Positive Delta (TOPIQ boosting score)
| Filename | KonIQ | TOPIQ | Existing | C6 | Delta |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 20250204_133404.jpg | 67.13 | 78.62 | 70.69 | 75.13 | +4.44 |
| 20240502_193823.jpg | 54.39 | 62.51 | 59.74 | 60.07 | +0.33 |
| 20250129_054504.jpg | 72.87 | 75.58 | 75.09 | 74.77 | -0.32 |
| 20250204_135520.jpg | 68.76 | 74.73 | 73.37 | 72.94 | -0.43 |
| 20231231_150055.jpg | 77.10 | 79.10 | 79.65 | 78.50 | -1.15 |

### Top 5 Negative Delta (TOPIQ dampening score)
| Filename | KonIQ | TOPIQ | Existing | C6 | Delta |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 20250129_102520.jpg | 37.23 | 33.09 | 44.78 | 34.33 | -10.45 |
| 1675564423029-24.jpg | 77.65 | 67.78 | 77.28 | 70.74 | -6.54 |
| 20250129_103313.jpg | 50.06 | 51.46 | 55.65 | 51.04 | -4.61 |
| IMG_2781.JPG | 63.17 | 65.55 | 67.78 | 64.83 | -2.95 |
| 20250217_144845.jpg | 68.05 | 70.45 | 72.25 | 69.73 | -2.52 |

### High Quality Images (C6 >= 65)
The following unique images maintained or achieved a C6 score >= 65:
- **20231231_150055.jpg** (78.50)
- **20250204_133404.jpg** (75.13)
- **20250129_054504.jpg** (74.77)
- **20250204_135520.jpg** (72.94)
- **20250204_163550.jpg** (72.13)
- **1675564423029-24.jpg** (70.74)
- **20250217_144845.jpg** (69.73)
- **IMG_2785.JPG** (66.95)

### Regressions (Existing >= 65, C6 < 65)
Images that would have been "A-cut" candidates under the old scoring but are excluded under C6:
| Filename | Existing | C6 | Reason |
| :--- | :--- | :--- | :--- |
| IMG_2781.JPG | 67.78 | 64.83 | TOPIQ (65.55) is lower than existing FLIVE-heavy score |
| 1720499657653.jpg | 66.40 | 64.54 | KonIQ (61.28) is lower than existing FLIVE score |

## 6. Risks
- **Cold Start Latency**: The maximum inference time (212ms) and preprocess time (64ms) occur on the first image after model load. While acceptable for background scoring, it should be monitored if more models are added.
- **Divergence**: Significant negative deltas (up to -10) suggest TOPIQ is more conservative than the legacy FLIVE-based technical score for some low-quality images.

## 7. Recommendation
**Decision: PASS**

The log-only smoke test confirms that the TOPIQ mixed112 model is running correctly on Android and producing valid C6 candidate scores that follow the intended dampening/boosting logic.

**Next Step**: **Larger Batch Test**. The current smoke test uses a limited set of images. A larger, more diverse dataset is required to confirm that the C6 threshold of 65 remains optimal for identifying high-quality photos before proceeding to a full parity test.
