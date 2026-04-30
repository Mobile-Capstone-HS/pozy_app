package com.example.pose_camera_app

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
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
                    "preloadModel" -> {
                        inferenceExecutor.execute {
                            val modelPath = call.argument<String>("modelPath")
                            val response = gemmaEngine.preloadModel(modelPath)
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "isModelLoaded" -> {
                        inferenceExecutor.execute {
                            val response = gemmaEngine.isModelLoaded()
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "generateAcutComment" -> {
                        val inputJson = call.argument<String>("inputJson")
                        if (inputJson.isNullOrBlank()) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to "missing_input_json",
                                ),
                            )
                            return@setMethodCallHandler
                        }

                        inferenceExecutor.execute {
                            val response = gemmaEngine.generateAcutComment(inputJson)
                            mainHandler.post { result.success(response) }
                        }
                    }

                    "disposeModel" -> {
                        inferenceExecutor.execute {
                            gemmaEngine.disposeModel()
                            mainHandler.post { result.success(mapOf("ok" to true)) }
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
}
