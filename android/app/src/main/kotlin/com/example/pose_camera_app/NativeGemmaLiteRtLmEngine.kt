package com.example.pose_camera_app

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.google.ai.edge.litertlm.Backend
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
    }

    private var engine: Engine? = null
    private var loadedModelPath: String? = null
    private var lastModelLoadTimeMs: Long? = null

    init {
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
    }

    fun preloadModel(modelPath: String?): Map<String, Any?> {
        val resolvedPath = resolveModelPath(modelPath)
        return try {
            ensureEngine(resolvedPath)
            Log.i(TAG, "preload ok modelPath=$resolvedPath loadMs=$lastModelLoadTimeMs")
            mapOf(
                "ok" to true,
                "model_loaded" to true,
                "model_path" to resolvedPath,
                "model_load_time_ms" to lastModelLoadTimeMs,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "preload failed", t)
            mapOf(
                "ok" to false,
                "model_loaded" to false,
                "model_path" to resolvedPath,
                "error" to t.message.orEmpty(),
            )
        }
    }

    fun isModelLoaded(): Map<String, Any?> =
        mapOf(
            "ok" to true,
            "model_loaded" to (engine != null),
            "model_path" to loadedModelPath,
            "model_load_time_ms" to lastModelLoadTimeMs,
        )

    @OptIn(ExperimentalApi::class)
    fun generateAcutComment(inputJson: String): Map<String, Any?> {
        val startedAt = SystemClock.elapsedRealtime()
        return try {
            val payload = JSONObject(inputJson)
            val resolvedPath = resolveModelPath(payload.optString("model_path"))
            val defaultCommentType =
                payload.optString("default_comment_type").ifBlank { "candidate_keep" }
            val prompt = payload.optString("prompt")
            if (prompt.isBlank()) {
                return mapOf(
                    "ok" to false,
                    "comment_type" to defaultCommentType,
                    "short_reason" to "",
                    "detailed_reason" to "",
                    "comparison_reason" to null,
                    "json_parse_success" to false,
                    "error" to "missing_prompt",
                    "model_load_time_ms" to lastModelLoadTimeMs,
                    "total_generation_time_ms" to (SystemClock.elapsedRealtime() - startedAt),
                )
            }

            val runtime = ensureEngine(resolvedPath)
            val rawText =
                runtime.createConversation().use { conversation ->
                    val response = conversation.sendMessage(prompt)
                    conversation.renderMessageIntoString(response, emptyMap()).trim()
                }

            val totalMs = SystemClock.elapsedRealtime() - startedAt
            val parsed = parseStructuredComment(rawText, defaultCommentType)
            val result =
                linkedMapOf<String, Any?>(
                    "ok" to (parsed["error"] == null),
                    "comment_type" to parsed["comment_type"],
                    "short_reason" to parsed["short_reason"],
                    "detailed_reason" to parsed["detailed_reason"],
                    "comparison_reason" to parsed["comparison_reason"],
                    "model_load_time_ms" to lastModelLoadTimeMs,
                    "total_generation_time_ms" to totalMs,
                    "json_parse_success" to (parsed["json_parse_success"] == true),
                    "error" to parsed["error"],
                    "raw_text" to rawText,
                )
            Log.i(
                TAG,
                "generate ok inputPath=$resolvedPath loadMs=$lastModelLoadTimeMs totalMs=$totalMs jsonParse=${parsed["json_parse_success"]}",
            )
            result
        } catch (t: Throwable) {
            Log.e(TAG, "generate failed", t)
            mapOf(
                "ok" to false,
                "comment_type" to "candidate_keep",
                "short_reason" to "",
                "detailed_reason" to "",
                "comparison_reason" to null,
                "model_load_time_ms" to lastModelLoadTimeMs,
                "total_generation_time_ms" to (SystemClock.elapsedRealtime() - startedAt),
                "json_parse_success" to false,
                "error" to t.message.orEmpty(),
            )
        }
    }

    fun disposeModel() {
        engine?.close()
        engine = null
        loadedModelPath = null
        lastModelLoadTimeMs = null
    }

    private fun ensureEngine(modelPath: String): Engine {
        val current = engine
        if (current != null && loadedModelPath == modelPath) {
            return current
        }

        val modelFile = File(modelPath)
        check(modelFile.exists()) { "model_not_found:$modelPath" }
        check(modelFile.canRead()) { "model_not_readable:$modelPath" }

        disposeModel()
        val config =
            EngineConfig(
                modelPath = modelPath,
                backend = Backend.CPU(),
                cacheDir = context.cacheDir.path,
            )

        val newEngine = Engine(config)
        val loadStartedAt = SystemClock.elapsedRealtime()
        newEngine.initialize()
        lastModelLoadTimeMs = SystemClock.elapsedRealtime() - loadStartedAt
        loadedModelPath = modelPath
        engine = newEngine
        return newEngine
    }

    private fun resolveModelPath(modelPath: String?): String {
        val normalized = modelPath?.trim().orEmpty()
        return if (normalized.isEmpty()) {
            DEFAULT_MODEL_PATH
        } else {
            normalized
        }
    }

    private fun parseStructuredComment(
        rawText: String,
        defaultCommentType: String,
    ): Map<String, Any?> {
        val normalized = stripMarkdownFence(rawText)
        return try {
            val json = JSONObject(normalized)
            mapOf(
                "comment_type" to json.optString("comment_type").ifBlank { defaultCommentType },
                "short_reason" to json.optString("short_reason"),
                "detailed_reason" to json.optString("detailed_reason"),
                "comparison_reason" to json.opt("comparison_reason")
                    .takeUnless { it == org.json.JSONObject.NULL }
                    ?.toString(),
                "json_parse_success" to true,
                "error" to null,
            )
        } catch (t: Throwable) {
            mapOf(
                "comment_type" to defaultCommentType,
                "short_reason" to "",
                "detailed_reason" to normalized,
                "comparison_reason" to null,
                "json_parse_success" to false,
                "error" to "json_parse_failed:${t.message.orEmpty()}",
            )
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
}
