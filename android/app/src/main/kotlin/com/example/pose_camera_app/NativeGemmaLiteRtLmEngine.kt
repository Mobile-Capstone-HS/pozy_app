package com.example.pose_camera_app

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.LogSeverity
import org.json.JSONObject
import java.io.File

class NativeGemmaLiteRtLmEngine(
    private val context: Context,
) {
    companion object {
        private const val TAG = "GemmaLiteRtLm"
        private const val DEFAULT_MODEL_PATH = "/data/local/tmp/llm/gemma4_e4b.litertlm"
        private const val PROMPT_MODE_COMPACT_REWRITE = "compact_rewrite"
        private const val ENGINE_CONFIG_MODE_DEFAULT_SAFE = "default_safe"
        private const val BACKEND_MODE_GPU_PREFERRED = "gpu_preferred"
        private const val BACKEND_MODE_CPU_ONLY = "cpu_only"
        private const val DECODING_CONFIG_LABEL_DEFAULT_SAFE = "default_safe"
        private const val DECODING_CONFIG_ENABLED = false
        private const val BACKEND_INFO_UNAVAILABLE = "backend_info_unavailable"
        private const val MANIFEST_OPENCL_DECLARED = true
        private const val MANIFEST_VNDK_SUPPORT_DECLARED = true
        private val OPENCL_LIBRARY_CANDIDATES =
            listOf(
                "/vendor/lib64/libOpenCL.so",
                "/system/vendor/lib64/libOpenCL.so",
                "/system/lib64/libOpenCL.so",
                "/vendor/lib/libOpenCL.so",
                "/system/lib/libOpenCL.so",
            )
    }

    private var engine: Engine? = null
    private var loadedModelPath: String? = null
    private var lastModelLoadTimeMs: Long? = null
    private var lastBackendInfo: String? = null
    private var loadedBackendMode: String? = null
    private var lastGpuFallbackUsed: Boolean = false
    private var lastGpuFallbackReason: String? = null
    private var visualEngine: Engine? = null
    private var loadedVisualModelPath: String? = null
    private var loadedVisualBackendMode: String? = null
    private var lastVisualModelLoadTimeMs: Long? = null

    private data class ParseRecovery(
        val commentType: String,
        val shortReason: String,
        val detailedReason: String,
        val comparisonReason: String?,
        val jsonParseSuccess: Boolean,
        val parseFailed: Boolean,
        val repaired: Boolean,
        val repairReason: String?,
        val fallbackUsed: Boolean,
        val parseFailureReason: String?,
        val fallbackReason: String?,
        val parseStrategy: String,
    )

    init {
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
    }

    fun checkModelFile(modelPath: String?): Map<String, Any?> {
        val resolvedPath = resolveModelPath(modelPath)
        val modelFile = File(resolvedPath)
        val fileExists = modelFile.exists()
        val fileSizeBytes = modelFile.lengthOrNegative()
        Log.i(
            TAG,
            "check model file model_path=$resolvedPath " +
                "model_file_exists=$fileExists " +
                "model_file_size_bytes=$fileSizeBytes",
        )
        return mapOf(
            "ok" to true,
            "model_path" to resolvedPath,
            "file_exists" to fileExists,
            "file_size_bytes" to fileSizeBytes,
        )
    }

    fun preloadModel(modelPath: String?, backendMode: String?): Map<String, Any?> {
        val resolvedPath = resolveModelPath(modelPath)
        val requestedBackendMode = normalizeBackendMode(backendMode)
        val modelFile = File(resolvedPath)
        val fileExists = modelFile.exists()
        val fileSizeBytes = modelFile.lengthOrNegative()
        logBackendDiagnostics(
            phase = "preload_start",
            modelPath = resolvedPath,
            modelFileExists = fileExists,
            modelFileSizeBytes = fileSizeBytes,
            backendMode = requestedBackendMode,
            backendInfo = backendInfoForLog(requestedBackendMode),
        )
        return try {
            val runtime = ensureEngine(resolvedPath, requestedBackendMode)
            val backendInfo = backendInfoForEngine(runtime)
            Log.i(
                TAG,
                "preload ok model_path=$resolvedPath " +
                    "model_file_exists=$fileExists " +
                    "model_file_size_bytes=$fileSizeBytes " +
                    "backend_request=$requestedBackendMode " +
                    "engine_config_mode=$requestedBackendMode " +
                    "decoding_config_enabled=$DECODING_CONFIG_ENABLED " +
                    "backend_info=$backendInfo " +
                    "gpu_fallback_used=$lastGpuFallbackUsed " +
                    "loadMs=$lastModelLoadTimeMs",
            )
            mapOf(
                "ok" to true,
                "model_loaded" to true,
                "model_path" to resolvedPath,
                "model_load_time_ms" to lastModelLoadTimeMs,
                "file_exists" to fileExists,
                "file_size_bytes" to fileSizeBytes,
                "engine_config_mode" to requestedBackendMode,
                "backend_request" to requestedBackendMode,
                "decoding_config_enabled" to DECODING_CONFIG_ENABLED,
                "decoding_config" to DECODING_CONFIG_LABEL_DEFAULT_SAFE,
                "backend_info" to backendInfo,
                "gpu_fallback_used" to lastGpuFallbackUsed,
                "gpu_fallback_reason" to lastGpuFallbackReason,
                "opencl_file_candidates" to openClCandidateSummary(),
            )
        } catch (t: Throwable) {
            Log.e(
                TAG,
                "preload failed model_path=$resolvedPath " +
                    "model_file_exists=$fileExists " +
                    "model_file_size_bytes=$fileSizeBytes " +
                    "backend_request=$requestedBackendMode " +
                    "engine_config_mode=$requestedBackendMode " +
                    "decoding_config_enabled=$DECODING_CONFIG_ENABLED " +
                    "backend_info=${backendInfoForLog(requestedBackendMode)} " +
                    "exceptionClass=${t.javaClass.name} " +
                    "exceptionMessage=${t.message.orEmpty()}",
                t,
            )
            mapOf(
                "ok" to false,
                "model_loaded" to false,
                "model_path" to resolvedPath,
                "file_exists" to fileExists,
                "file_size_bytes" to fileSizeBytes,
                "engine_config_mode" to requestedBackendMode,
                "backend_request" to requestedBackendMode,
                "decoding_config_enabled" to DECODING_CONFIG_ENABLED,
                "decoding_config" to DECODING_CONFIG_LABEL_DEFAULT_SAFE,
                "backend_info" to backendInfoForLog(requestedBackendMode),
                "gpu_fallback_used" to lastGpuFallbackUsed,
                "gpu_fallback_reason" to lastGpuFallbackReason,
                "opencl_file_candidates" to openClCandidateSummary(),
                "error" to "${t.javaClass.simpleName}: ${t.message.orEmpty()}",
            )
        }
    }

    fun isModelLoaded(): Map<String, Any?> =
        mapOf(
            "ok" to true,
            "model_loaded" to (engine != null),
            "model_path" to loadedModelPath,
            "model_load_time_ms" to lastModelLoadTimeMs,
            "engine_config_mode" to (loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "backend_request" to (loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "decoding_config_enabled" to DECODING_CONFIG_ENABLED,
            "decoding_config" to DECODING_CONFIG_LABEL_DEFAULT_SAFE,
            "backend_info" to backendInfoForLog(loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "gpu_fallback_used" to lastGpuFallbackUsed,
            "gpu_fallback_reason" to lastGpuFallbackReason,
            "opencl_file_candidates" to openClCandidateSummary(),
        )

    @OptIn(ExperimentalApi::class)
    fun generateAcutComment(inputJson: String, backendMode: String?): Map<String, Any?> {
        val startedAt = SystemClock.elapsedRealtime()
        val payload = JSONObject(inputJson)
        val resolvedPath = resolveModelPath(payload.optString("model_path"))
        val requestedBackendMode =
            normalizeBackendMode(
                backendMode ?: payload.optString("backend_mode"),
            )
        val requestedCommentType =
            canonicalizeRequestedCommentType(payload.optString("default_comment_type"))
        val promptMode = payload.optString("prompt_mode").ifBlank { PROMPT_MODE_COMPACT_REWRITE }
        val prompt = payload.optString("prompt")
        Log.i(
            TAG,
            "generate start inputPath=$resolvedPath " +
                "backend_request=$requestedBackendMode " +
                "prompt_mode=$promptMode " +
                "prompt_chars=${prompt.length} " +
                "engine_config_mode=$requestedBackendMode " +
                "decoding_config_enabled=$DECODING_CONFIG_ENABLED " +
                "backend_info=${backendInfoForLog(requestedBackendMode)} " +
                "opencl_candidates=${openClCandidateSummary()}",
        )
        if (prompt.isBlank()) {
            val totalMs = SystemClock.elapsedRealtime() - startedAt
            val recovery =
                buildFallbackRecovery(
                    requestedCommentType = requestedCommentType,
                    parseFailureReason = "missing_prompt",
                    parseStrategy = "no_prompt",
                    forceNullComparisonReason = true,
                )
            val result =
                buildGenerateResult(
                    recovery = recovery,
                    rawText = "",
                    modelLoadTimeMs = lastModelLoadTimeMs,
                    nativeGenerationTimeMs = 0L,
                    totalGenerationTimeMs = totalMs,
                )
            logGenerateResult(
                resolvedPath = resolvedPath,
                modelLoadTimeMs = lastModelLoadTimeMs,
                nativeGenerationTimeMs = 0L,
                totalGenerationTimeMs = totalMs,
                outputLength = 0,
                rawOutputPreview = "",
                promptChars = prompt.length,
                promptMode = promptMode,
                jsonParseSuccess = false,
                fallbackUsed = recovery.fallbackUsed,
                parseFailureReason = "missing_prompt",
            )
            return result
        }

        val runtime = ensureEngine(resolvedPath, requestedBackendMode)
        val backendInfo = backendInfoForEngine(runtime)
        val generationStartedAt = SystemClock.elapsedRealtime()
        val rawText =
            runtime.createConversation().use { conversation ->
                val response = conversation.sendMessage(prompt)
                conversation.renderMessageIntoString(response, emptyMap()).trim()
            }
        val nativeGenerationMs = SystemClock.elapsedRealtime() - generationStartedAt
        val totalMs = SystemClock.elapsedRealtime() - startedAt
        val recovery =
            parseStructuredComment(
                rawText = rawText,
                requestedCommentType = requestedCommentType,
                forceNullComparisonReason = promptMode == PROMPT_MODE_COMPACT_REWRITE,
            )
        val result =
            buildGenerateResult(
                recovery = recovery,
                rawText = rawText,
                modelLoadTimeMs = lastModelLoadTimeMs,
                nativeGenerationTimeMs = nativeGenerationMs,
                totalGenerationTimeMs = totalMs,
            )
        logGenerateResult(
            resolvedPath = resolvedPath,
            modelLoadTimeMs = lastModelLoadTimeMs,
            nativeGenerationTimeMs = nativeGenerationMs,
            totalGenerationTimeMs = totalMs,
            outputLength = rawText.length,
            rawOutputPreview = previewText(rawText),
            promptChars = prompt.length,
            promptMode = promptMode,
            jsonParseSuccess = recovery.jsonParseSuccess,
            fallbackUsed = recovery.fallbackUsed,
            parseFailureReason = recovery.parseFailureReason,
            backendInfo = backendInfo,
        )
        return result
    }

    @OptIn(ExperimentalApi::class)
    fun generateAcutVisualComment(
        prompt: String?,
        imagePath: String?,
        modelPath: String?,
        backendMode: String?,
        defaultCommentType: String?,
        forceNullComparisonReason: Boolean,
    ): Map<String, Any?> {
        val startedAt = SystemClock.elapsedRealtime()
        val resolvedPath = resolveModelPath(modelPath)
        val requestedBackendMode = normalizeBackendMode(backendMode)
        val requestedCommentType = canonicalizeRequestedCommentType(defaultCommentType)
        val normalizedPrompt = prompt?.trim().orEmpty()
        val normalizedImagePath = imagePath?.trim().orEmpty()
        val imageFile = File(normalizedImagePath)
        val imageFileExists = normalizedImagePath.isNotBlank() && imageFile.exists()
        val imageFileSizeBytes = if (imageFileExists) imageFile.length() else -1L

        Log.i(
            TAG,
            "visual probe start model_path=$resolvedPath " +
                "backend_request=$requestedBackendMode " +
                "prompt_chars=${normalizedPrompt.length} " +
                "image_path=$normalizedImagePath " +
                "image_file_exists=$imageFileExists " +
                "image_file_size_bytes=$imageFileSizeBytes",
        )

        if (normalizedPrompt.isBlank()) {
            return visualUnsupportedOrInvalidResult(
                startedAt = startedAt,
                reason = "missing_prompt",
                imagePath = normalizedImagePath,
                imageFileExists = imageFileExists,
                imageFileSizeBytes = imageFileSizeBytes,
                backendMode = requestedBackendMode,
            )
        }
        if (!imageFileExists || !imageFile.canRead()) {
            return visualUnsupportedOrInvalidResult(
                startedAt = startedAt,
                reason = if (normalizedImagePath.isBlank()) "missing_image_path" else "image_file_not_readable",
                imagePath = normalizedImagePath,
                imageFileExists = imageFileExists,
                imageFileSizeBytes = imageFileSizeBytes,
                backendMode = requestedBackendMode,
            )
        }

        val generationStartedAt = SystemClock.elapsedRealtime()
        return try {
            val loadStartedAt = SystemClock.elapsedRealtime()
            val runtime = ensureVisualEngine(resolvedPath, requestedBackendMode)
            val visualLoadMs = lastVisualModelLoadTimeMs ?: (SystemClock.elapsedRealtime() - loadStartedAt)
            val backendInfo = backendInfoForEngine(runtime)

            val contents =
                Contents.Companion.of(
                    Content.ImageFile(imageFile.absolutePath),
                    Content.Text(normalizedPrompt),
                )
            val responseText =
                runtime.createConversation().use { conversation ->
                    val response = conversation.sendMessage(contents)
                    conversation.renderMessageIntoString(response, emptyMap()).trim()
                }
            val nativeGenerationMs = SystemClock.elapsedRealtime() - generationStartedAt
            val totalMs = SystemClock.elapsedRealtime() - startedAt
            val recovery =
                parseStructuredComment(
                    rawText = responseText,
                    requestedCommentType = requestedCommentType,
                    forceNullComparisonReason = forceNullComparisonReason,
                )
            val rawPreview = previewText(responseText)
            Log.i(
                TAG,
                "visual probe ok model_path=$resolvedPath " +
                    "backend_info=$backendInfo " +
                    "image_input_used=true " +
                    "vision_or_prefill_ms=$visualLoadMs " +
                    "native_generation_ms=$nativeGenerationMs " +
                    "total_ms=$totalMs " +
                    "output_length=${responseText.length} " +
                    "rawPreview=$rawPreview",
            )
            linkedMapOf(
                "ok" to true,
                "output" to responseText,
                "comment_type" to recovery.commentType,
                "short_reason" to recovery.shortReason,
                "detailed_reason" to recovery.detailedReason,
                "comparison_reason" to recovery.comparisonReason,
                "image_input_supported" to true,
                "image_input_used" to true,
                "image_path" to imageFile.absolutePath,
                "image_file_exists" to imageFileExists,
                "image_file_size_bytes" to imageFileSizeBytes,
                "image_preprocess_ms" to null,
                "vision_or_prefill_ms" to visualLoadMs,
                "native_generation_ms" to nativeGenerationMs,
                "total_ms" to totalMs,
                "backend_info" to backendInfo,
                "gpu_fallback_used" to false,
                "json_parse_success" to recovery.jsonParseSuccess,
                "parse_failed" to recovery.parseFailed,
                "repaired" to recovery.repaired,
                "repair_reason" to recovery.repairReason,
                "fallback_used" to recovery.fallbackUsed,
                "fallback_reason" to recovery.fallbackReason,
                "raw_preview" to rawPreview,
                "model_path" to resolvedPath,
                "backend_request" to requestedBackendMode,
                "prompt_chars" to normalizedPrompt.length,
                "output_length" to responseText.length,
                "error" to null,
            )
        } catch (t: Throwable) {
            val totalMs = SystemClock.elapsedRealtime() - startedAt
            Log.e(
                TAG,
                "visual probe failed model_path=$resolvedPath " +
                    "backend_request=$requestedBackendMode " +
                    "image_path=$normalizedImagePath " +
                    "exceptionClass=${t.javaClass.name} " +
                    "exceptionMessage=${t.message.orEmpty()} " +
                    "total_ms=$totalMs",
                t,
            )
            linkedMapOf(
                "ok" to false,
                "output" to "",
                "image_input_supported" to true,
                "image_input_used" to false,
                "reason" to "image_input_api_found_but_probe_failed",
                "image_path" to normalizedImagePath,
                "image_file_exists" to imageFileExists,
                "image_file_size_bytes" to imageFileSizeBytes,
                "image_preprocess_ms" to null,
                "vision_or_prefill_ms" to null,
                "native_generation_ms" to null,
                "total_ms" to totalMs,
                "backend_info" to backendInfoForLog(requestedBackendMode),
                "gpu_fallback_used" to false,
                "json_parse_success" to false,
                "parse_failed" to false,
                "repaired" to false,
                "repair_reason" to null,
                "fallback_used" to false,
                "fallback_reason" to null,
                "raw_preview" to "",
                "model_path" to resolvedPath,
                "backend_request" to requestedBackendMode,
                "prompt_chars" to normalizedPrompt.length,
                "output_length" to 0,
                "error" to "${t.javaClass.simpleName}: ${t.message.orEmpty()}",
            )
        }
    }

    fun disposeModel() {
        engine?.close()
        visualEngine?.close()
        engine = null
        visualEngine = null
        loadedModelPath = null
        loadedVisualModelPath = null
        lastModelLoadTimeMs = null
        lastVisualModelLoadTimeMs = null
        lastBackendInfo = null
        loadedBackendMode = null
        loadedVisualBackendMode = null
        lastGpuFallbackUsed = false
        lastGpuFallbackReason = null
    }

    private fun ensureEngine(modelPath: String, backendMode: String): Engine {
        val current = engine
        if (current != null && loadedModelPath == modelPath && loadedBackendMode == backendMode) {
            return current
        }

        val modelFile = File(modelPath)
        check(modelFile.exists()) { "model_not_found:$modelPath" }
        check(modelFile.canRead()) { "model_not_readable:$modelPath" }

        disposeModel()
        val loadStartedAt = SystemClock.elapsedRealtime()
        val newEngine =
            if (backendMode == BACKEND_MODE_GPU_PREFERRED) {
                try {
                    createInitializedEngine(
                        modelPath = modelPath,
                        backend = Backend.GPU(),
                    )
                } catch (t: Throwable) {
                    val elapsedMs = SystemClock.elapsedRealtime() - loadStartedAt
                    lastGpuFallbackUsed = true
                    lastGpuFallbackReason = "${t.javaClass.simpleName}: ${t.message.orEmpty()}"
                    Log.w(
                        TAG,
                        "gpu engine init failed, falling back to CPU " +
                            "exceptionClass=${t.javaClass.name} " +
                            "exceptionMessage=${t.message.orEmpty()} " +
                            "elapsed_ms=$elapsedMs",
                        t,
                    )
                    createInitializedEngine(
                        modelPath = modelPath,
                        backend = Backend.CPU(),
                    )
                }
            } else {
                lastGpuFallbackUsed = false
                lastGpuFallbackReason = null
                createInitializedEngine(
                    modelPath = modelPath,
                    backend = Backend.CPU(),
                )
            }
        lastModelLoadTimeMs = SystemClock.elapsedRealtime() - loadStartedAt
        loadedModelPath = modelPath
        loadedBackendMode = backendMode
        lastBackendInfo = backendInfoForEngine(newEngine)
        engine = newEngine
        return newEngine
    }

    private fun createInitializedEngine(modelPath: String, backend: Backend): Engine {
        val config =
            EngineConfig(
                modelPath = modelPath,
                backend = backend,
                cacheDir = context.cacheDir.path,
            )

        val newEngine = Engine(config)
        return try {
            newEngine.initialize()
            newEngine
        } catch (t: Throwable) {
            try {
                newEngine.close()
            } catch (_: Throwable) {
                // Best-effort cleanup after failed native initialization.
            }
            throw t
        }
    }

    private fun ensureVisualEngine(modelPath: String, backendMode: String): Engine {
        val current = visualEngine
        if (
            current != null &&
            loadedVisualModelPath == modelPath &&
            loadedVisualBackendMode == backendMode
        ) {
            Log.i(
                TAG,
                "visual engine reuse=true model_path=$modelPath backend_mode=$backendMode"
            )
            return current
        }

        val modelFile = File(modelPath)
        check(modelFile.exists()) { "model_not_found:$modelPath" }
        check(modelFile.canRead()) { "model_not_readable:$modelPath" }
        Log.i(
            TAG,
            "visual engine reuse=false, creating new engine. model_path=$modelPath backend_mode=$backendMode"
        )

        visualEngine?.close()
        visualEngine = null
        val backend = backendForMode(backendMode)
        val config =
            EngineConfig(
                modelPath = modelPath,
                backend = backend,
                visionBackend = backend,
                maxNumImages = 1,
                cacheDir = context.cacheDir.path,
            )
        val loadStartedAt = SystemClock.elapsedRealtime()
        val newEngine = Engine(config)
        try {
            newEngine.initialize()
        } catch (t: Throwable) {
            try {
                newEngine.close()
            } catch (_: Throwable) {
                // Best-effort cleanup after failed native initialization.
            }
            throw t
        }
        lastVisualModelLoadTimeMs = SystemClock.elapsedRealtime() - loadStartedAt
        loadedVisualModelPath = modelPath
        loadedVisualBackendMode = backendMode
        visualEngine = newEngine
        return newEngine
    }

    private fun backendForMode(backendMode: String): Backend {
        return if (backendMode == BACKEND_MODE_GPU_PREFERRED) {
            Backend.GPU()
        } else {
            Backend.CPU()
        }
    }

    private fun visualUnsupportedOrInvalidResult(
        startedAt: Long,
        reason: String,
        imagePath: String,
        imageFileExists: Boolean,
        imageFileSizeBytes: Long,
        backendMode: String,
    ): Map<String, Any?> {
        return linkedMapOf(
            "ok" to false,
            "output" to "",
            "image_input_supported" to true,
            "image_input_used" to false,
            "reason" to reason,
            "image_path" to imagePath,
            "image_file_exists" to imageFileExists,
            "image_file_size_bytes" to imageFileSizeBytes,
            "image_preprocess_ms" to null,
            "vision_or_prefill_ms" to null,
            "native_generation_ms" to null,
            "total_ms" to (SystemClock.elapsedRealtime() - startedAt),
            "backend_info" to backendInfoForLog(backendMode),
            "gpu_fallback_used" to false,
            "json_parse_success" to false,
            "parse_failed" to false,
            "repaired" to false,
            "repair_reason" to null,
            "fallback_used" to false,
            "fallback_reason" to reason,
            "raw_preview" to "",
            "backend_request" to backendMode,
            "error" to reason,
        )
    }

    private fun resolveModelPath(modelPath: String?): String {
        val normalized = modelPath?.trim().orEmpty()
        return if (normalized.isEmpty()) {
            DEFAULT_MODEL_PATH
        } else {
            normalized
        }
    }

    private fun buildGenerateResult(
        recovery: ParseRecovery,
        rawText: String,
        modelLoadTimeMs: Long?,
        nativeGenerationTimeMs: Long,
        totalGenerationTimeMs: Long,
    ): Map<String, Any?> {
        return linkedMapOf(
            "ok" to true,
            "comment_type" to recovery.commentType,
            "short_reason" to recovery.shortReason,
            "detailed_reason" to recovery.detailedReason,
            "comparison_reason" to recovery.comparisonReason,
            "model_load_time_ms" to modelLoadTimeMs,
            "native_generation_time_ms" to nativeGenerationTimeMs,
            "total_generation_time_ms" to totalGenerationTimeMs,
            "json_parse_success" to recovery.jsonParseSuccess,
            "parse_failed" to recovery.parseFailed,
            "repaired" to recovery.repaired,
            "repair_reason" to recovery.repairReason,
            "fallback_used" to recovery.fallbackUsed,
            "parse_failure_reason" to recovery.parseFailureReason,
            "fallback_reason" to recovery.fallbackReason,
            "parse_strategy" to recovery.parseStrategy,
            "output_length" to rawText.length,
            "raw_output_preview" to previewText(rawText),
            "engine_config_mode" to (loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "backend_request" to (loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "decoding_config_enabled" to DECODING_CONFIG_ENABLED,
            "decoding_config" to DECODING_CONFIG_LABEL_DEFAULT_SAFE,
            "backend_info" to backendInfoForLog(loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
            "gpu_fallback_used" to lastGpuFallbackUsed,
            "gpu_fallback_reason" to lastGpuFallbackReason,
            "opencl_file_candidates" to openClCandidateSummary(),
            "error" to null,
        )
    }

    private fun parseStructuredComment(
        rawText: String,
        requestedCommentType: String,
        forceNullComparisonReason: Boolean,
    ): ParseRecovery {
        if (rawText.isBlank()) {
            return buildFallbackRecovery(
                requestedCommentType = requestedCommentType,
                parseFailureReason = "empty_raw_output",
                parseStrategy = "empty_raw_output",
                forceNullComparisonReason = forceNullComparisonReason,
            )
        }

        val attempts =
            linkedMapOf(
                "raw" to rawText,
                "special_tokens_removed" to stripSpecialTokens(rawText),
                "codeblock_stripped" to stripMarkdownFence(rawText),
                "brace_substring" to extractJsonSubstring(stripSpecialTokens(rawText)),
                "trimmed" to rawText.trim(),
            )

        var lastFailureReason = "json_parse_failed:unknown"
        for ((strategy, candidate) in attempts) {
            if (candidate.isBlank()) {
                continue
            }

            try {
                val json = JSONObject(candidate)
                return canonicalizeParsedJson(
                    json = json,
                    requestedCommentType = requestedCommentType,
                    parseStrategy = strategy,
                    forceNullComparisonReason = forceNullComparisonReason,
                )
            } catch (t: Throwable) {
                lastFailureReason = "$strategy:${t.message.orEmpty()}"
            }
        }

        return buildFallbackRecovery(
            requestedCommentType = requestedCommentType,
            parseFailureReason = lastFailureReason,
            parseStrategy = "fallback_after_parse_failure",
            forceNullComparisonReason = forceNullComparisonReason,
        )
    }

    private fun canonicalizeParsedJson(
        json: JSONObject,
        requestedCommentType: String,
        parseStrategy: String,
        forceNullComparisonReason: Boolean,
    ): ParseRecovery {
        val fallbackReasons = mutableListOf<String>()
        val repairReasons = mutableListOf<String>()

        val emittedCommentType =
            cleanText(json.opt("comment_type"))?.let(::canonicalizeRequestedCommentType)
        if (emittedCommentType == null) {
            fallbackReasons.add("missing_required_field:comment_type")
        } else if (emittedCommentType != requestedCommentType) {
            repairReasons.add(
                "comment_type_adjusted:$emittedCommentType->$requestedCommentType",
            )
        }

        val parsedShortReason = cleanText(json.opt("short_reason"))
        val shortReason =
            parsedShortReason ?: fallbackShortReason(requestedCommentType).also {
                fallbackReasons.add("missing_required_field:short_reason")
            }

        val parsedDetailedReason = cleanText(json.opt("detailed_reason"))
        val detailedReason =
            parsedDetailedReason ?: fallbackDetailedReason(requestedCommentType, shortReason).also {
                fallbackReasons.add("missing_required_field:detailed_reason")
            }

        val comparisonReason =
            if (forceNullComparisonReason) {
                if (json.has("comparison_reason")) {
                    repairReasons.add("comparison_reason_forced_null")
                }
                null
            } else {
                normalizeComparisonReason(json.opt("comparison_reason")).also {
                    if (it == null && json.has("comparison_reason")) {
                        val rawComparison = json.opt("comparison_reason")
                        if (rawComparison != null && rawComparison != JSONObject.NULL) {
                            val rawText = rawComparison.toString().trim()
                            if (rawText.equals("null", ignoreCase = true) || rawText.isEmpty()) {
                                repairReasons.add("comparison_reason_normalized_to_null")
                            }
                        }
                    }
                }
            }

        if (parseStrategy != "raw") {
            repairReasons.add(parseStrategy)
        }

        val fallbackUsed = fallbackReasons.isNotEmpty()
        val repaired = repairReasons.isNotEmpty()
        return ParseRecovery(
            commentType = requestedCommentType,
            shortReason = shortReason,
            detailedReason = detailedReason,
            comparisonReason = comparisonReason,
            jsonParseSuccess = true,
            parseFailed = false,
            repaired = repaired,
            repairReason = repairReasons.joinToString(", ").takeIf { it.isNotBlank() },
            fallbackUsed = fallbackUsed,
            parseFailureReason = null,
            fallbackReason = fallbackReasons.joinToString(", ").takeIf { it.isNotBlank() },
            parseStrategy = parseStrategy,
        )
    }

    private fun buildFallbackRecovery(
        requestedCommentType: String,
        parseFailureReason: String,
        parseStrategy: String,
        forceNullComparisonReason: Boolean,
    ): ParseRecovery {
        val shortReason = fallbackShortReason(requestedCommentType)
        return ParseRecovery(
            commentType = requestedCommentType,
            shortReason = shortReason,
            detailedReason = fallbackDetailedReason(requestedCommentType, shortReason),
            comparisonReason = if (forceNullComparisonReason) null else null,
            jsonParseSuccess = false,
            parseFailed = true,
            repaired = false,
            repairReason = null,
            fallbackUsed = true,
            parseFailureReason = parseFailureReason,
            fallbackReason = parseFailureReason,
            parseStrategy = parseStrategy,
        )
    }

    private fun canonicalizeRequestedCommentType(value: String?): String {
        return when (value?.trim()) {
            "selected_explanation",
            "strong_pick",
            -> "selected_explanation"

            "near_miss_feedback",
            "candidate_keep",
            -> "near_miss_feedback"

            "rejection_reason",
            "retry_recommended",
            -> "rejection_reason"

            else -> "near_miss_feedback"
        }
    }

    private fun fallbackShortReason(commentType: String): String {
        return when (commentType) {
            "selected_explanation" ->
                "점수상으로는 대표 컷 후보로 볼 수 있는 장면입니다."

            "rejection_reason" ->
                "현재 점수 기준으로는 다른 컷을 우선 검토하는 편이 안전합니다."

            else ->
                "전반적인 완성도는 무난하지만 더 좋은 후보가 있을 수 있습니다."
        }
    }

    private fun fallbackDetailedReason(commentType: String, shortReason: String): String {
        return when (commentType) {
            "selected_explanation" ->
                "$shortReason 기술 점수와 미적 점수를 함께 반영했을 때 전반적으로 안정적인 결과로 해석할 수 있습니다."

            "rejection_reason" ->
                "$shortReason 현재 결과는 품질이나 인상 측면에서 아쉬움이 있어 재촬영 또는 다른 후보 검토가 더 적절합니다."

            else ->
                "$shortReason 현재 결과는 활용 가능하지만 같은 세트 안에서 더 높은 완성도의 대안이 있을 수 있습니다."
        }
    }

    private fun normalizeComparisonReason(value: Any?): String? {
        if (value == null || value == JSONObject.NULL) {
            return null
        }
        val normalized = value.toString().trim()
        if (normalized.isEmpty() || normalized.equals("null", ignoreCase = true)) {
            return null
        }
        return normalized.take(128)
    }

    private fun cleanText(value: Any?): String? {
        if (value == null || value == JSONObject.NULL) {
            return null
        }
        val text = value.toString().trim()
        if (text.isEmpty() || text.equals("null", ignoreCase = true)) {
            return null
        }
        return text
    }

    private fun extractJsonSubstring(rawText: String): String {
        val firstBrace = rawText.indexOf('{')
        val lastBrace = rawText.lastIndexOf('}')
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            return ""
        }
        return rawText.substring(firstBrace, lastBrace + 1)
    }

    private fun previewText(rawText: String, maxLength: Int = 200): String {
        val normalized = rawText.replace('\n', ' ').trim()
        if (normalized.isEmpty()) {
            return ""
        }
        return if (normalized.length <= maxLength) {
            normalized
        } else {
            normalized.substring(0, maxLength) + "..."
        }
    }

    private fun logGenerateResult(
        resolvedPath: String,
        modelLoadTimeMs: Long?,
        nativeGenerationTimeMs: Long,
        totalGenerationTimeMs: Long,
        outputLength: Int,
        rawOutputPreview: String,
        promptChars: Int,
        promptMode: String,
        jsonParseSuccess: Boolean,
        fallbackUsed: Boolean,
        parseFailureReason: String?,
        backendInfo: String = backendInfoForLog(loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED),
    ) {
        val repaired = jsonParseSuccess && fallbackUsed
        Log.i(
            TAG,
            "generate ok inputPath=$resolvedPath " +
                "loadMs=${modelLoadTimeMs ?: -1} " +
                "backend_request=${loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED} " +
                "engine_config_mode=${loadedBackendMode ?: BACKEND_MODE_GPU_PREFERRED} " +
                "decoding_config_enabled=$DECODING_CONFIG_ENABLED " +
                "prompt_mode=$promptMode " +
                "prompt_chars=$promptChars " +
                "native_generation_ms=$nativeGenerationTimeMs " +
                "totalMs=$totalGenerationTimeMs " +
                "output_length=$outputLength " +
                "jsonParse=$jsonParseSuccess " +
                "repaired=$repaired " +
                "fallbackUsed=$fallbackUsed " +
                "backend_info=$backendInfo " +
                "gpu_fallback_used=$lastGpuFallbackUsed " +
                "opencl_candidates=${openClCandidateSummary()} " +
                "rawPreview=$rawOutputPreview " +
                "parseFailureReason=${parseFailureReason ?: "none"}",
        )
    }

    private fun logBackendDiagnostics(
        phase: String,
        modelPath: String,
        modelFileExists: Boolean,
        modelFileSizeBytes: Long,
        backendMode: String,
        backendInfo: String,
    ) {
        Log.i(
            TAG,
            "backend diagnostics phase=$phase " +
                "backend_request=$backendMode " +
                "model_path=$modelPath " +
                "model_file_exists=$modelFileExists " +
                "model_file_size_bytes=$modelFileSizeBytes " +
                "manifest_opencl_declared=$MANIFEST_OPENCL_DECLARED " +
                "manifest_vndksupport_declared=$MANIFEST_VNDK_SUPPORT_DECLARED " +
                "engine_config_mode=$backendMode " +
                "decoding_config_enabled=$DECODING_CONFIG_ENABLED " +
                "nativeLibraryDir=${context.applicationInfo.nativeLibraryDir} " +
                "supported_abis=${Build.SUPPORTED_ABIS.joinToString(",")} " +
                "backend_info=$backendInfo",
        )
        Log.i(TAG, "opencl_candidates=${openClCandidateSummary()}")
    }

    private fun backendInfoForLog(backendMode: String): String {
        return engine?.let(::backendInfoForEngine)
            ?: lastBackendInfo
            ?: configuredBackendInfo(backendMode)
    }

    private fun backendInfoForEngine(runtime: Engine): String {
        return runtime.engineConfig.backend?.name?.takeIf { it.isNotBlank() }
            ?: BACKEND_INFO_UNAVAILABLE
    }

    private fun configuredBackendInfo(backendMode: String): String {
        val backend =
            if (backendMode == BACKEND_MODE_GPU_PREFERRED) {
                Backend.GPU()
            } else {
                Backend.CPU()
            }
        return backend.name.takeIf { it.isNotBlank() } ?: BACKEND_INFO_UNAVAILABLE
    }

    private fun normalizeBackendMode(backendMode: String?): String {
        return when (backendMode?.trim()) {
            BACKEND_MODE_CPU_ONLY -> BACKEND_MODE_CPU_ONLY
            BACKEND_MODE_GPU_PREFERRED -> BACKEND_MODE_GPU_PREFERRED
            else -> BACKEND_MODE_GPU_PREFERRED
        }
    }

    private fun openClCandidateSummary(): String {
        return OPENCL_LIBRARY_CANDIDATES.joinToString(" ") { path ->
            "$path exists=${File(path).exists()}"
        }
    }

    private fun stripMarkdownFence(rawText: String): String {
        var normalized = rawText.trim()
        if (normalized.startsWith("```json")) {
            normalized = normalized.substring(7)
        } else if (normalized.startsWith("```")) {
            normalized = normalized.substring(3)
        }
        if (normalized.endsWith("```")) {
            normalized = normalized.substring(0, normalized.length - 3)
        }
        return normalized.trim()
    }

    private fun stripSpecialTokens(rawText: String): String {
        return rawText
            .replace("<|turn|>model", "")
            .replace("<|turn|>user", "")
            .replace("<|turn>model", "")
            .replace("<|turn>user", "")
            .replace("<|end_of_turn|>", "")
            .replace("<|end|>", "")
            .trim()
    }

    private fun File.lengthOrNegative(): Long {
        return if (exists()) {
            length()
        } else {
            -1L
        }
    }
}
