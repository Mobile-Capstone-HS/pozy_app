package com.example.pose_camera_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

class NativeFastScnnEngine(
    private val context: Context,
    private val emitEvent: (Map<String, Any>) -> Unit,
) {
    companion object {
        private const val TAG = "FastSCNN"
    }

    private var interpreter: Interpreter? = null
    private var inputHeight: Int = 0
    private var inputWidth: Int = 0
    private var outputShape: IntArray = intArrayOf()
    private var outputElementCount: Int = 0
    private var outputIsHwc: Boolean = true
    private val numClasses = 19

    fun initialize(modelAssetPath: String, numThreads: Int): Map<String, Any> {
        dispose()
        val start = SystemClock.elapsedRealtimeNanos()
        return try {
            val mappedModel = loadModelFile(modelAssetPath)
            val options =
                Interpreter.Options().apply {
                    setNumThreads(numThreads.coerceAtLeast(1))
                }
            interpreter = Interpreter(mappedModel, options)

            val inShape = interpreter!!.getInputTensor(0).shape()
            val outShape = interpreter!!.getOutputTensor(0).shape()
            inputHeight = inShape[1]
            inputWidth = inShape[2]
            outputShape = outShape
            outputElementCount = outShape.fold(1) { acc, dim -> acc * dim }
            outputIsHwc = outShape.size == 4 && outShape[3] == numClasses

            val totalMs = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
            Log.i(
                TAG,
                "initialize ok input=${inputWidth}x$inputHeight output=${outShape.contentToString()} ${"%.1f".format(totalMs)}ms",
            )
            emitEvent(mapOf("type" to "status", "state" to "initialized"))
            emitEvent(
                mapOf(
                    "type" to "perf",
                    "stage" to "initialize",
                    "totalMs" to totalMs,
                ),
            )

            mapOf(
                "ok" to true,
                "inputWidth" to inputWidth,
                "inputHeight" to inputHeight,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "initialize failed", t)
            emitEvent(
                mapOf(
                    "type" to "error",
                    "message" to "initialize_failed:${t.message.orEmpty()}",
                ),
            )
            mapOf(
                "ok" to false,
                "reason" to "initialize_failed",
                "message" to t.message.orEmpty(),
            )
        }
    }

    fun segment(jpegBytes: ByteArray): Map<String, Any> {
        val runtime =
            interpreter ?: return mapOf("ok" to false, "reason" to "not_initialized")

        return try {
            val t0 = SystemClock.elapsedRealtimeNanos()
            val decoded =
                BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                    ?: return mapOf("ok" to false, "reason" to "decode_failed")
            val resized = Bitmap.createScaledBitmap(decoded, inputWidth, inputHeight, true)
            val t1 = SystemClock.elapsedRealtimeNanos()

            val input = bitmapToInputBuffer(resized)
            val t2 = SystemClock.elapsedRealtimeNanos()

            val output = runOutput(runtime, input)
            val t3 = SystemClock.elapsedRealtimeNanos()

            val classMapBytes = argmaxToFlatClassMapByteArray(output)
            val t4 = SystemClock.elapsedRealtimeNanos()

            emitPerfEvent(t0, t2, t3, t4)

            mapOf(
                "ok" to true,
                "width" to inputWidth,
                "height" to inputHeight,
                "classMapBytes" to classMapBytes,
            )
        } catch (t: Throwable) {
            emitEvent(
                mapOf(
                    "type" to "error",
                    "message" to "segment_failed:${t.message.orEmpty()}",
                ),
            )
            mapOf(
                "ok" to false,
                "reason" to "segment_failed",
                "message" to t.message.orEmpty(),
            )
        }
    }

    fun segmentYuv420(
        width: Int,
        height: Int,
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        rotationQuarterTurns: Int,
        mirrorX: Boolean,
    ): Map<String, Any> {
        val runtime =
            interpreter ?: return mapOf("ok" to false, "reason" to "not_initialized")

        return try {
            val t0 = SystemClock.elapsedRealtimeNanos()
            val input =
                yuv420ToInputBuffer(
                    width = width,
                    height = height,
                    yPlane = yPlane,
                    uPlane = uPlane,
                    vPlane = vPlane,
                    yRowStride = yRowStride,
                    uvRowStride = uvRowStride,
                    uvPixelStride = uvPixelStride,
                    rotationQuarterTurns = rotationQuarterTurns,
                    mirrorX = mirrorX,
                )
            val t1 = SystemClock.elapsedRealtimeNanos()

            val output = runOutput(runtime, input)
            val t2 = SystemClock.elapsedRealtimeNanos()

            val classMapBytes = argmaxToFlatClassMapByteArray(output)
            val t3 = SystemClock.elapsedRealtimeNanos()

            emitPerfEvent(t0, t1, t2, t3)

            mapOf(
                "ok" to true,
                "width" to inputWidth,
                "height" to inputHeight,
                "classMapBytes" to classMapBytes,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "segmentYuv420 failed", t)
            emitEvent(
                mapOf(
                    "type" to "error",
                    "message" to "segment_yuv420_failed:${t.message.orEmpty()}",
                ),
            )
            mapOf(
                "ok" to false,
                "reason" to "segment_yuv420_failed",
                "message" to t.message.orEmpty(),
            )
        }
    }

    fun dispose() {
        interpreter?.close()
        interpreter = null
        inputHeight = 0
        inputWidth = 0
        outputShape = intArrayOf()
        outputElementCount = 0
    }

    private fun runOutput(runtime: Interpreter, input: ByteBuffer): FloatArray {
        val outputBuffer =
            ByteBuffer.allocateDirect(outputElementCount * 4).order(ByteOrder.nativeOrder())
        runtime.run(input, outputBuffer)
        outputBuffer.rewind()
        val output = FloatArray(outputElementCount)
        outputBuffer.asFloatBuffer().get(output)
        return output
    }

    private fun bitmapToInputBuffer(bitmap: Bitmap): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(inputHeight * inputWidth * 3 * 4)
        buffer.order(ByteOrder.nativeOrder())
        val pixels = IntArray(inputHeight * inputWidth)
        bitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight)

        var i = 0
        while (i < pixels.size) {
            val pixel = pixels[i]
            val r = (pixel shr 16) and 0xFF
            val g = (pixel shr 8) and 0xFF
            val b = pixel and 0xFF
            buffer.putFloat(r / 255.0f)
            buffer.putFloat(g / 255.0f)
            buffer.putFloat(b / 255.0f)
            i++
        }

        buffer.rewind()
        return buffer
    }

    private fun yuv420ToInputBuffer(
        width: Int,
        height: Int,
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        rotationQuarterTurns: Int,
        mirrorX: Boolean,
    ): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(inputHeight * inputWidth * 3 * 4)
        buffer.order(ByteOrder.nativeOrder())

        var yOut = 0
        while (yOut < inputHeight) {
            var xOut = 0
            while (xOut < inputWidth) {
                var nx = (xOut + 0.5f) / inputWidth
                val ny = (yOut + 0.5f) / inputHeight

                if (mirrorX) {
                    nx = 1.0f - nx
                }

                val (rx, ry) = inverseRotate(nx, ny, rotationQuarterTurns)
                val srcX = ((rx * width).toInt()).coerceIn(0, width - 1)
                val srcY = ((ry * height).toInt()).coerceIn(0, height - 1)
                val yIdx = srcY * yRowStride + srcX
                val uvIdx = (srcY / 2) * uvRowStride + (srcX / 2) * uvPixelStride

                val yVal = (yPlane[yIdx].toInt() and 0xFF).toFloat()
                val uVal = (uPlane[uvIdx].toInt() and 0xFF) - 128.0f
                val vVal = (vPlane[uvIdx].toInt() and 0xFF) - 128.0f

                val r = clampToByte(yVal + 1.402f * vVal)
                val g = clampToByte(yVal - 0.344136f * uVal - 0.714136f * vVal)
                val b = clampToByte(yVal + 1.772f * uVal)

                buffer.putFloat(r / 255.0f)
                buffer.putFloat(g / 255.0f)
                buffer.putFloat(b / 255.0f)
                xOut++
            }
            yOut++
        }

        buffer.rewind()
        return buffer
    }

    private fun inverseRotate(x: Float, y: Float, turns: Int): Pair<Float, Float> {
        return when ((turns % 4 + 4) % 4) {
            1 -> Pair(1.0f - y, x)
            2 -> Pair(1.0f - x, 1.0f - y)
            3 -> Pair(y, 1.0f - x)
            else -> Pair(x, y)
        }
    }

    private fun clampToByte(value: Float): Float {
        if (value < 0f) return 0f
        if (value > 255f) return 255f
        return value
    }

    private fun emitPerfEvent(t0: Long, t1: Long, t2: Long, t3: Long) {
        val preprocessMs = (t1 - t0) / 1_000_000.0
        val inferenceMs = (t2 - t1) / 1_000_000.0
        val postprocessMs = (t3 - t2) / 1_000_000.0
        val totalMs = (t3 - t0) / 1_000_000.0
        emitEvent(
            mapOf(
                "type" to "perf",
                "preprocessMs" to preprocessMs,
                "inferenceMs" to inferenceMs,
                "postprocessMs" to postprocessMs,
                "totalMs" to totalMs,
            ),
        )
    }

    private fun argmaxToFlatClassMapByteArray(output: FloatArray): ByteArray {
        val flat = ByteArray(inputHeight * inputWidth)

        var y = 0
        while (y < inputHeight) {
            var x = 0
            while (x < inputWidth) {
                var bestClass = 0
                var bestScore = Float.NEGATIVE_INFINITY
                var c = 0
                while (c < numClasses) {
                    val idx =
                        if (outputIsHwc) {
                            ((y * inputWidth + x) * numClasses) + c
                        } else {
                            (c * inputHeight * inputWidth) + (y * inputWidth) + x
                        }
                    val score = output[idx]
                    if (score > bestScore) {
                        bestScore = score
                        bestClass = c
                    }
                    c++
                }
                flat[y * inputWidth + x] = bestClass.toByte()
                x++
            }
            y++
        }

        return flat
    }

    private fun loadModelFile(assetPath: String): MappedByteBuffer {
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        val lookupKey = flutterLoader.getLookupKeyForAsset(assetPath)
        val fileDescriptor = context.assets.openFd(lookupKey)
        FileInputStream(fileDescriptor.fileDescriptor).use { input ->
            val channel = input.channel
            return channel.map(
                FileChannel.MapMode.READ_ONLY,
                fileDescriptor.startOffset,
                fileDescriptor.declaredLength,
            )
        }
    }
}
