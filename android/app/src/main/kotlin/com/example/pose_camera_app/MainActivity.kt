package com.example.pose_camera_app

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val fastScnnMethodChannelName = "pozy.fastscnn/method"
    private val fastScnnEventChannelName = "pozy.fastscnn/event"
    private val gemmaMethodChannelName = "pozy.gemma_litertlm/method"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inferenceExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private lateinit var fastScnnEngine: NativeFastScnnEngine
    private lateinit var gemmaEngine: NativeGemmaLiteRtLmEngine
    private val gemmaGenerationBusy = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fastScnnEngine = NativeFastScnnEngine(
            context = applicationContext,
            emitEvent = { event ->
                mainHandler.post { eventSink?.success(event) }
            },
        )
        gemmaEngine = NativeGemmaLiteRtLmEngine(
            context = applicationContext,
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fastScnnMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        inferenceExecutor.execute {
                            val assetPath =
                                call.argument<String>("modelAssetPath")
                                    ?: "assets/models/fastscnn_cityscapes_float16.tflite"
                            val numThreads = call.argument<Int>("numThreads") ?: 2
                            val response = fastScnnEngine.initialize(assetPath, numThreads)
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "segment" -> {
                        val jpegBytes = call.argument<ByteArray>("jpegBytes")
                        if (jpegBytes == null || jpegBytes.isEmpty()) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "reason" to "invalid_jpeg_bytes",
                                ),
                            )
                            return@setMethodCallHandler
                        }
                        inferenceExecutor.execute {
                            val response = fastScnnEngine.segment(jpegBytes)
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "segmentYuv420" -> {
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val yPlane = call.argument<ByteArray>("yPlane")
                        val uPlane = call.argument<ByteArray>("uPlane")
                        val vPlane = call.argument<ByteArray>("vPlane")
                        val yRowStride = call.argument<Int>("yRowStride") ?: 0
                        val uvRowStride = call.argument<Int>("uvRowStride") ?: 0
                        val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
                        val rotationQuarterTurns =
                            (call.argument<Int>("rotationQuarterTurns") ?: 0) % 4
                        val mirrorX = call.argument<Boolean>("mirrorX") == true

                        if (width <= 0 ||
                            height <= 0 ||
                            yPlane == null ||
                            uPlane == null ||
                            vPlane == null
                        ) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "reason" to "invalid_yuv420_input",
                                ),
                            )
                            return@setMethodCallHandler
                        }

                        inferenceExecutor.execute {
                            val response = fastScnnEngine.segmentYuv420(
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
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "dispose" -> {
                        inferenceExecutor.execute {
                            fastScnnEngine.dispose()
                            mainHandler.post { result.success(mapOf("ok" to true)) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, gemmaMethodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkModelFile" -> {
                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                val modelPath = call.argument<String>("modelPath")
                                val response = gemmaEngine.checkModelFile(modelPath)
                                postSuccessOnce(result, responded, response)
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_check_model_failed",
                                    message = t.message.orEmpty(),
                                )
                            }
                        }
                    }

                    "preloadModel" -> {
                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                val modelPath = call.argument<String>("modelPath")
                                val backendMode = call.argument<String>("backendMode")
                                val response = gemmaEngine.preloadModel(modelPath, backendMode)
                                postSuccessOnce(result, responded, response)
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_preload_failed",
                                    message = t.message.orEmpty(),
                                )
                            }
                        }
                    }

                    "isModelLoaded" -> {
                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                val response = gemmaEngine.isModelLoaded()
                                postSuccessOnce(result, responded, response)
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_status_failed",
                                    message = t.message.orEmpty(),
                                )
                            }
                        }
                    }

                    "generateAcutComment" -> {
                        val inputJson = call.argument<String>("inputJson")
                        if (inputJson.isNullOrBlank()) {
                            result.error(
                                "missing_input_json",
                                "missing_input_json",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        if (!gemmaGenerationBusy.compareAndSet(false, true)) {
                            result.error(
                                "gemma_generation_busy",
                                "gemma_generation_busy",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                val backendMode = call.argument<String>("backendMode")
                                val response = gemmaEngine.generateAcutComment(
                                    inputJson = inputJson,
                                    backendMode = backendMode,
                                )
                                postSuccessOnce(result, responded, response)
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_generate_failed",
                                    message = t.message.orEmpty(),
                                )
                            } finally {
                                gemmaGenerationBusy.set(false)
                            }
                        }
                    }

                    "generateAcutVisualComment" -> {
                        if (!gemmaGenerationBusy.compareAndSet(false, true)) {
                            result.error(
                                "gemma_generation_busy",
                                "gemma_generation_busy",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                val prompt = call.argument<String>("prompt")
                                val imagePath = call.argument<String>("imagePath")
                                val modelPath = call.argument<String>("modelPath")
                                val backendMode = call.argument<String>("backendMode")
                                val defaultCommentType =
                                    call.argument<String>("defaultCommentType")
                                val forceNullComparisonReason =
                                    call.argument<Boolean>("forceNullComparisonReason") != false
                                val response = gemmaEngine.generateAcutVisualComment(
                                    prompt = prompt,
                                    imagePath = imagePath,
                                    modelPath = modelPath,
                                    backendMode = backendMode,
                                    defaultCommentType = defaultCommentType,
                                    forceNullComparisonReason = forceNullComparisonReason,
                                )
                                postSuccessOnce(result, responded, response)
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_visual_probe_failed",
                                    message = t.message.orEmpty(),
                                )
                            } finally {
                                gemmaGenerationBusy.set(false)
                            }
                        }
                    }

                    "disposeModel" -> {
                        val responded = AtomicBoolean(false)
                        inferenceExecutor.execute {
                            try {
                                gemmaEngine.disposeModel()
                                postSuccessOnce(result, responded, mapOf("ok" to true))
                            } catch (t: Throwable) {
                                postErrorOnce(
                                    result = result,
                                    responded = responded,
                                    code = "gemma_dispose_failed",
                                    message = t.message.orEmpty(),
                                )
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, fastScnnEventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    events?.success(mapOf("type" to "status", "state" to "ready"))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onDestroy() {
        fastScnnEngine.dispose()
        gemmaEngine.disposeModel()
        inferenceExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun postSuccessOnce(
        result: MethodChannel.Result,
        responded: AtomicBoolean,
        value: Any?,
    ) {
        if (!responded.compareAndSet(false, true)) {
            return
        }
        mainHandler.post { result.success(value) }
    }

    private fun postErrorOnce(
        result: MethodChannel.Result,
        responded: AtomicBoolean,
        code: String,
        message: String,
    ) {
        if (!responded.compareAndSet(false, true)) {
            return
        }
        mainHandler.post { result.error(code, message, null) }
    }
}
