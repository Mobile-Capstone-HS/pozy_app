package com.ultralytics.yolo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.tensorflow.lite.Interpreter
import java.io.BufferedReader
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

private data class PortraitFaceMetrics(
    val detected: Boolean = false,
    val yaw: Double? = null,
    val pitch: Double? = null,
    val roll: Double? = null,
    val leftEyeOpen: Double? = null,
    val rightEyeOpen: Double? = null,
    val smile: Double? = null,
    val bounds: Rect? = null,
)

private data class PortraitLightingMetrics(
    val code: Double = 5.0, // unknown
    val confidence: Double = 0.0,
)

private data class PortraitFaceResult(
    val left: Double,
    val top: Double,
    val right: Double,
    val bottom: Double,
    val leftEyeOpenProbability: Double? = null,
    val rightEyeOpenProbability: Double? = null,
    val smilingProbability: Double? = null,
    val headEulerAngleY: Double? = null,
    val headEulerAngleZ: Double? = null,
    val headEulerAngleX: Double? = null,
    val imageWidth: Int,
    val imageHeight: Int,
    val rotationDegrees: Int,
    val isFrontCamera: Boolean,
    val timestampMs: Long,
    val frameNumber: Long,
    val confidenceStatus: String,
)

class PortraitNativeAnalyzer(
    private val context: Context,
) {
    private val tag = "PortraitNativeAnalyzer"
    private val faceDetector: FaceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .build(),
    )
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val faceBusy = AtomicBoolean(false)
    private val lightingBusy = AtomicBoolean(false)
    private var faceFrameCounter = 0
    private var lightingFrameCounter = 0

    @Volatile
    private var latestFaceMetrics = PortraitFaceMetrics()

    @Volatile
    private var latestLightingMetrics = PortraitLightingMetrics()

    @Volatile
    private var latestFaceResultsPayload: Map<String, Any> = emptyMap()

    private var lightingInterpreter: Interpreter? = null
    private var lightingLabels: List<String> = emptyList()
    private var lightingLoaded = false
    private var analyzerFrameCounter = 0L
    private var faceIntervalMs = DEFAULT_FACE_INTERVAL_MS
    private var faceIntervalFrames = DEFAULT_FACE_INTERVAL_FRAMES
    private var lastFaceAnalysisAtMs = 0L

    companion object {
        private const val LIGHTING_SIZE = 224
        private const val LIGHTING_MIN_CONFIDENCE = 0.55
        private const val DEFAULT_FACE_INTERVAL_MS = 180
        private const val DEFAULT_FACE_INTERVAL_FRAMES = 6
        private const val LIGHTING_INTERVAL = 1
    }

    fun ensureReady() {
        if (!lightingLoaded) {
            loadLightingModel()
        }
    }

    fun setFaceAnalysisThrottle(intervalMs: Int?, intervalFrames: Int?) {
        faceIntervalMs = (intervalMs ?: DEFAULT_FACE_INTERVAL_MS).coerceIn(0, 1000)
        faceIntervalFrames =
            (intervalFrames ?: DEFAULT_FACE_INTERVAL_FRAMES).coerceIn(1, 120)
    }

    fun schedule(
        imageProxy: ImageProxy,
        bitmap: Bitmap,
        isFrontCamera: Boolean,
    ) {
        ensureReady()
        analyzerFrameCounter += 1L
        faceFrameCounter++
        lightingFrameCounter++
        val nowMs = System.currentTimeMillis()
        val faceDueByFrame = faceFrameCounter >= faceIntervalFrames
        val faceDueByTime = nowMs - lastFaceAnalysisAtMs >= faceIntervalMs
        if (faceDueByFrame && faceDueByTime) {
            faceFrameCounter = 0
            lastFaceAnalysisAtMs = nowMs
            scheduleFaceAnalysis(
                imageProxy = imageProxy,
                isFrontCamera = isFrontCamera,
                frameNumber = analyzerFrameCounter,
            )
        }
        if (lightingFrameCounter >= LIGHTING_INTERVAL) {
            lightingFrameCounter = 0
            scheduleLightingAnalysis(bitmap)
        }
    }

    fun latestMetrics(): Map<String, Any> {
        val face = latestFaceMetrics
        val lighting = latestLightingMetrics
        val metrics = hashMapOf<String, Any>(
            "portraitFaceDetected" to if (face.detected) 1.0 else 0.0,
            "portraitLightingCode" to lighting.code,
            "portraitLightingConfidence" to lighting.confidence,
        )
        face.yaw?.let { metrics["portraitFaceYaw"] = it }
        face.pitch?.let { metrics["portraitFacePitch"] = it }
        face.roll?.let { metrics["portraitFaceRoll"] = it }
        face.leftEyeOpen?.let { metrics["portraitLeftEyeOpen"] = it }
        face.rightEyeOpen?.let { metrics["portraitRightEyeOpen"] = it }
        face.smile?.let { metrics["portraitSmileProbability"] = it }
        return metrics
    }

    fun latestFaceResults(): Map<String, Any> = latestFaceResultsPayload

    fun dispose() {
        scope.cancel()
        faceDetector.close()
        lightingInterpreter?.close()
        lightingInterpreter = null
        faceFrameCounter = 0
        lightingFrameCounter = 0
        latestFaceResultsPayload = emptyMap()
    }

    private fun scheduleFaceAnalysis(
        imageProxy: ImageProxy,
        isFrontCamera: Boolean,
        frameNumber: Long,
    ) {
        if (!faceBusy.compareAndSet(false, true)) return

        val nv21 = runCatching { ImageUtils.toNv21(imageProxy) }.getOrNull()
        if (nv21 == null) {
            latestFaceMetrics = PortraitFaceMetrics()
            latestFaceResultsPayload = emptyMap()
            faceBusy.set(false)
            return
        }
        val width = imageProxy.width
        val height = imageProxy.height
        val rotation = imageProxy.imageInfo.rotationDegrees
        val timestampMs = System.currentTimeMillis()

        scope.launch {
            try {
                val inputImage = InputImage.fromByteArray(
                    nv21,
                    width,
                    height,
                    rotation,
                    InputImage.IMAGE_FORMAT_NV21,
                )
                val faces = faceDetector.process(inputImage).getResultSafely()
                latestFaceResultsPayload = buildFaceResultsPayload(
                    faces = faces,
                    imageWidth = width,
                    imageHeight = height,
                    rotationDegrees = rotation,
                    isFrontCamera = isFrontCamera,
                    timestampMs = timestampMs,
                    frameNumber = frameNumber,
                )
                val bestFace = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                latestFaceMetrics = if (bestFace != null) {
                    PortraitFaceMetrics(
                        detected = true,
                        yaw = bestFace.headEulerAngleY.toDouble(),
                        pitch = bestFace.headEulerAngleX.toDouble(),
                        roll = bestFace.headEulerAngleZ.toDouble(),
                        leftEyeOpen = bestFace.leftEyeOpenProbability?.toDouble(),
                        rightEyeOpen = bestFace.rightEyeOpenProbability?.toDouble(),
                        smile = bestFace.smilingProbability?.toDouble(),
                        bounds = Rect(bestFace.boundingBox),
                    )
                } else {
                    PortraitFaceMetrics()
                }
            } catch (e: Exception) {
                Log.w(tag, "Face analysis failed", e)
                latestFaceMetrics = PortraitFaceMetrics()
                latestFaceResultsPayload = emptyMap()
            } finally {
                faceBusy.set(false)
            }
        }
    }

    private fun scheduleLightingAnalysis(bitmap: Bitmap) {
        if (!lightingLoaded || !lightingBusy.compareAndSet(false, true)) return

        scope.launch {
            try {
                val bestFace = latestFaceMetrics.bounds
                if (bestFace == null) {
                    latestLightingMetrics = PortraitLightingMetrics()
                } else {
                    latestLightingMetrics = runLighting(bitmap, bestFace)
                }
            } catch (e: Exception) {
                Log.w(tag, "Lighting analysis failed", e)
                latestLightingMetrics = PortraitLightingMetrics()
            } finally {
                lightingBusy.set(false)
            }
        }
    }

    private fun runLighting(bitmap: Bitmap, faceBounds: Rect): PortraitLightingMetrics {
        val interpreter = lightingInterpreter ?: return PortraitLightingMetrics()
        val faceRect = expandFaceRect(faceBounds, bitmap.width, bitmap.height)
        val cropped = cropAndResize(bitmap, faceRect, LIGHTING_SIZE, LIGHTING_SIZE)
            ?: return PortraitLightingMetrics()

        val input = ByteBuffer.allocateDirect(4 * LIGHTING_SIZE * LIGHTING_SIZE * 3)
            .order(ByteOrder.nativeOrder())
        for (y in 0 until LIGHTING_SIZE) {
            for (x in 0 until LIGHTING_SIZE) {
                val pixel = cropped.getPixel(x, y)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                val luminance = (0.299f * r + 0.587f * g + 0.114f * b)
                input.putFloat(luminance)
                input.putFloat(luminance)
                input.putFloat(luminance)
            }
        }
        input.rewind()

        val output = Array(1) { FloatArray(max(lightingLabels.size, 5)) }
        interpreter.run(input, output)
        val probabilities = output[0]
        var maxIndex = 0
        var maxValue = Float.NEGATIVE_INFINITY
        probabilities.forEachIndexed { index, value ->
            if (value > maxValue) {
                maxValue = value
                maxIndex = index
            }
        }
        if (maxIndex >= lightingLabels.size) {
            return PortraitLightingMetrics()
        }

        val code = labelToCode(lightingLabels[maxIndex])
        val confidence = maxValue.toDouble()
        return if (confidence >= LIGHTING_MIN_CONFIDENCE) {
            PortraitLightingMetrics(code = code, confidence = confidence)
        } else {
            PortraitLightingMetrics()
        }
    }

    private fun loadLightingModel() {
        if (lightingLoaded) return
        try {
            val modelPathCandidates = listOf(
                "flutter_assets/assets/models/lighting_model.tflite",
                "assets/models/lighting_model.tflite",
                "models/lighting_model.tflite",
            )
            val labelPathCandidates = listOf(
                "flutter_assets/assets/models/lighting_labels.txt",
                "assets/models/lighting_labels.txt",
                "models/lighting_labels.txt",
            )

            val modelBuffer = modelPathCandidates.firstNotNullOfOrNull { path ->
                runCatching { YOLOUtils.loadModelFile(context, path) }.getOrNull()
            }
            val labels = labelPathCandidates.firstNotNullOfOrNull { path ->
                runCatching {
                    context.assets.open(path).bufferedReader().use(BufferedReader::readLines)
                }.getOrNull()
            }?.map(String::trim)?.filter(String::isNotEmpty)

            if (modelBuffer == null || labels.isNullOrEmpty()) {
                Log.w(tag, "Lighting model assets not found")
                return
            }

            lightingInterpreter = Interpreter(modelBuffer, Interpreter.Options().apply {
                setNumThreads(2)
            })
            lightingLabels = labels
            lightingLoaded = true
        } catch (e: Exception) {
            Log.w(tag, "Failed to load lighting model", e)
        }
    }

    private fun expandFaceRect(faceRect: Rect, width: Int, height: Int): Rect {
        val cx = faceRect.centerX().toFloat()
        val cy = faceRect.centerY().toFloat()
        val expandedW = faceRect.width() * 1.35f
        val expandedH = faceRect.height() * 1.55f
        val left = max(0f, cx - expandedW / 2f).toInt()
        val top = max(0f, cy - expandedH / 2f).toInt()
        val right = min(width.toFloat(), cx + expandedW / 2f).toInt()
        val bottom = min(height.toFloat(), cy + expandedH / 2f).toInt()
        return Rect(left, top, max(left + 1, right), max(top + 1, bottom))
    }

    private fun cropAndResize(bitmap: Bitmap, rect: Rect, width: Int, height: Int): Bitmap? {
        return try {
            val safeLeft = rect.left.coerceIn(0, bitmap.width - 1)
            val safeTop = rect.top.coerceIn(0, bitmap.height - 1)
            val safeWidth = rect.width().coerceIn(1, bitmap.width - safeLeft)
            val safeHeight = rect.height().coerceIn(1, bitmap.height - safeTop)
            Bitmap.createScaledBitmap(
                Bitmap.createBitmap(bitmap, safeLeft, safeTop, safeWidth, safeHeight),
                width,
                height,
                true,
            )
        } catch (e: Exception) {
            Log.w(tag, "cropAndResize failed", e)
            null
        }
    }

    private fun labelToCode(label: String): Double {
        return when (label) {
            "front_light" -> 0.0
            "short_light" -> 1.0
            "side_light" -> 2.0
            "rim_light" -> 3.0
            "back_light" -> 4.0
            else -> 5.0
        }
    }

    private fun buildFaceResultsPayload(
        faces: List<Face>,
        imageWidth: Int,
        imageHeight: Int,
        rotationDegrees: Int,
        isFrontCamera: Boolean,
        timestampMs: Long,
        frameNumber: Long,
    ): Map<String, Any> {
        val results = faces.map { face ->
            val bounds = face.boundingBox
            val confidenceStatus = faceConfidenceStatus(
                bounds = bounds,
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                hasEyeProb = face.leftEyeOpenProbability != null &&
                    face.rightEyeOpenProbability != null,
            )
            val result = PortraitFaceResult(
                left = bounds.left.toDouble(),
                top = bounds.top.toDouble(),
                right = bounds.right.toDouble(),
                bottom = bounds.bottom.toDouble(),
                leftEyeOpenProbability = face.leftEyeOpenProbability?.toDouble(),
                rightEyeOpenProbability = face.rightEyeOpenProbability?.toDouble(),
                smilingProbability = face.smilingProbability?.toDouble(),
                headEulerAngleY = face.headEulerAngleY.toDouble(),
                headEulerAngleZ = face.headEulerAngleZ.toDouble(),
                headEulerAngleX = face.headEulerAngleX.toDouble(),
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                rotationDegrees = rotationDegrees,
                isFrontCamera = isFrontCamera,
                timestampMs = timestampMs,
                frameNumber = frameNumber,
                confidenceStatus = confidenceStatus,
            )
            faceResultToMap(result)
        }

        return hashMapOf(
            "count" to results.size,
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "rotationDegrees" to rotationDegrees,
            "isFrontCamera" to isFrontCamera,
            "timestampMs" to timestampMs,
            "frameNumber" to frameNumber,
            "faces" to ArrayList(results),
        )
    }

    private fun faceResultToMap(result: PortraitFaceResult): Map<String, Any> {
        val map = hashMapOf<String, Any>(
            "left" to result.left,
            "top" to result.top,
            "right" to result.right,
            "bottom" to result.bottom,
            "imageWidth" to result.imageWidth,
            "imageHeight" to result.imageHeight,
            "rotationDegrees" to result.rotationDegrees,
            "isFrontCamera" to result.isFrontCamera,
            "timestampMs" to result.timestampMs,
            "frameNumber" to result.frameNumber,
            "confidenceStatus" to result.confidenceStatus,
        )
        result.leftEyeOpenProbability?.let { map["leftEyeOpenProbability"] = it }
        result.rightEyeOpenProbability?.let { map["rightEyeOpenProbability"] = it }
        result.smilingProbability?.let { map["smilingProbability"] = it }
        result.headEulerAngleY?.let { map["headEulerAngleY"] = it }
        result.headEulerAngleZ?.let { map["headEulerAngleZ"] = it }
        result.headEulerAngleX?.let { map["headEulerAngleX"] = it }
        return map
    }

    private fun faceConfidenceStatus(
        bounds: Rect,
        imageWidth: Int,
        imageHeight: Int,
        hasEyeProb: Boolean,
    ): String {
        if (imageWidth <= 0 || imageHeight <= 0 || bounds.width() <= 0 || bounds.height() <= 0) {
            return "uncertain"
        }
        if (
            bounds.left < 0 ||
            bounds.top < 0 ||
            bounds.right > imageWidth ||
            bounds.bottom > imageHeight
        ) {
            return "out_of_bounds"
        }
        val imageArea = imageWidth.toDouble() * imageHeight.toDouble()
        val faceArea = bounds.width().toDouble() * bounds.height().toDouble()
        if (imageArea <= 0.0 || faceArea <= 0.0) return "uncertain"
        if (faceArea / imageArea < 0.006) return "small"
        if (!hasEyeProb) return "uncertain"
        return "usable"
    }
}

private fun <T> com.google.android.gms.tasks.Task<T>.getResultSafely(): T {
    return com.google.android.gms.tasks.Tasks.await(this)
}
