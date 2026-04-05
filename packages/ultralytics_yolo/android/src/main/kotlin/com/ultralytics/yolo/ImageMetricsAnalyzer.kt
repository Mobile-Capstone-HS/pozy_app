package com.ultralytics.yolo

import android.graphics.Bitmap

/**
 * Computes brightness, blur, and exposure metrics from a camera Bitmap.
 * Called on the camera executor thread (not main thread).
 *
 * Every N frames to avoid unnecessary computation — caller controls throttling.
 */
object ImageMetricsAnalyzer {

    /**
     * Analyze the given bitmap and return a map of metrics ready to send via EventChannel.
     *
     * @param bitmap   The camera frame bitmap (may be rotated by YOLOView before calling)
     * @param roiLeft  Subject ROI in normalized coords (0.0–1.0), or null if no subject detected
     * @param roiTop
     * @param roiRight
     * @param roiBottom
     */
    fun analyze(
        bitmap: Bitmap,
        roiLeft: Float? = null,
        roiTop: Float? = null,
        roiRight: Float? = null,
        roiBottom: Float? = null,
    ): Map<String, Any> {
        // Scale bitmap to 160×120 for fast pixel iteration
        val scaled = Bitmap.createScaledBitmap(bitmap, 160, 120, false)
        val w = scaled.width
        val h = scaled.height
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        scaled.recycle()

        // Determine ROI bounds in pixel coords
        val hasRoi = roiLeft != null && roiTop != null && roiRight != null && roiBottom != null
        val roiX0 = if (hasRoi) (roiLeft!! * w).toInt().coerceIn(0, w - 1) else 0
        val roiY0 = if (hasRoi) (roiTop!! * h).toInt().coerceIn(0, h - 1) else 0
        val roiX1 = if (hasRoi) (roiRight!! * w).toInt().coerceIn(0, w - 1) else w - 1
        val roiY1 = if (hasRoi) (roiBottom!! * h).toInt().coerceIn(0, h - 1) else h - 1

        var globalLumaSum = 0.0
        var subjectLumaSum = 0.0
        var bgLumaSum = 0.0
        var globalCount = 0
        var subjectCount = 0
        var bgCount = 0

        var highlightCount = 0  // luma >= 235
        var shadowCount = 0     // luma <= 35
        var subjectHighlightCount = 0
        var subjectShadowCount = 0

        // Laplacian variance for blur (global)
        val lumaArray = FloatArray(w * h)

        for (y in 0 until h) {
            for (x in 0 until w) {
                val pixel = pixels[y * w + x]
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                val luma = 0.299 * r + 0.587 * g + 0.114 * b

                lumaArray[y * w + x] = luma.toFloat()
                globalLumaSum += luma
                globalCount++

                if (luma >= 235.0) highlightCount++
                if (luma <= 35.0) shadowCount++

                val inRoi = hasRoi &&
                        x in roiX0..roiX1 &&
                        y in roiY0..roiY1

                if (inRoi) {
                    subjectLumaSum += luma
                    subjectCount++
                    if (luma >= 235.0) subjectHighlightCount++
                    if (luma <= 35.0) subjectShadowCount++
                } else if (hasRoi) {
                    bgLumaSum += luma
                    bgCount++
                }
            }
        }

        val globalBrightness = if (globalCount > 0) (globalLumaSum / globalCount / 255.0) else 0.5
        val subjectBrightness = when {
            subjectCount > 0 -> subjectLumaSum / subjectCount / 255.0
            else -> globalBrightness
        }
        val backgroundBrightness = when {
            bgCount > 0 -> bgLumaSum / bgCount / 255.0
            else -> globalBrightness
        }
        val highlightRatio = if (globalCount > 0) highlightCount.toDouble() / globalCount else 0.0
        val shadowRatio = if (globalCount > 0) shadowCount.toDouble() / globalCount else 0.0
        val subjectHighlightRatio = when {
            subjectCount > 0 -> subjectHighlightCount.toDouble() / subjectCount
            else -> highlightRatio
        }
        val subjectShadowRatio = when {
            subjectCount > 0 -> subjectShadowCount.toDouble() / subjectCount
            else -> shadowRatio
        }

        // Laplacian variance (blur detection) — global
        val globalBlurScore = laplacianVariance(lumaArray, w, h, 0, 0, w - 1, h - 1)

        // Subject blur score
        val subjectBlurScore = if (hasRoi && subjectCount > 4) {
            laplacianVariance(lumaArray, w, h, roiX0, roiY0, roiX1, roiY1)
        } else {
            globalBlurScore
        }

        return mapOf(
            "brightness" to globalBrightness,
            "subjectBrightness" to subjectBrightness,
            "backgroundBrightness" to backgroundBrightness,
            "highlightRatio" to highlightRatio,
            "shadowRatio" to shadowRatio,
            "subjectHighlightRatio" to subjectHighlightRatio,
            "subjectShadowRatio" to subjectShadowRatio,
            "globalBlurScore" to globalBlurScore,
            "subjectBlurScore" to subjectBlurScore,
        )
    }

    private fun laplacianVariance(
        luma: FloatArray, w: Int, h: Int,
        x0: Int, y0: Int, x1: Int, y1: Int,
    ): Double {
        var sum = 0.0
        var sumSq = 0.0
        var count = 0

        for (y in (y0 + 1) until y1) {
            for (x in (x0 + 1) until x1) {
                val lap = (
                    -luma[(y - 1) * w + x] +
                    -luma[y * w + (x - 1)] +
                    4 * luma[y * w + x] +
                    -luma[y * w + (x + 1)] +
                    -luma[(y + 1) * w + x]
                ).toDouble()
                sum += lap
                sumSq += lap * lap
                count++
            }
        }
        if (count == 0) return 999.0
        val mean = sum / count
        return sumSq / count - mean * mean
    }
}
