package io.manxia.manxia

import android.content.Context
import androidx.annotation.RequiresApi
import androidx.javascriptengine.IsolateStartupParameters
import androidx.javascriptengine.JavaScriptSandbox
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

@RequiresApi(26)
internal class ScriptSourceHost(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "io.manxia/source-script")
    private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.SECONDS, ArrayBlockingQueue(8))
    private var sandbox: JavaScriptSandbox? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "evaluate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val code = call.arguments as? String
            if (code.isNullOrBlank() || code.toByteArray(Charsets.UTF_8).size > 192 * 1024) {
                result.error("size", "脚本执行输入超过大小限制", null)
                return@setMethodCallHandler
            }
            val queuedAt = System.nanoTime()
            try {
                worker.execute { evaluate(code, queuedAt, result) }
            } catch (_: RejectedExecutionException) {
                result.error("busy", "脚本源正在处理其他请求，请稍后重试", null)
            }
        }
    }

    private fun runtime(): JavaScriptSandbox {
        sandbox?.let { return it }
        check(JavaScriptSandbox.isSupported()) { "当前 Android WebView 不支持隔离脚本" }
        val connection = JavaScriptSandbox.createConnectedInstanceAsync(context)
        val runtime = try {
            connection.get(5, TimeUnit.SECONDS)
        } catch (error: TimeoutException) {
            connection.addListener({ runCatching { connection.get().close() } }, Executor { it.run() })
            throw error
        }
        if (!runtime.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_ISOLATE_TERMINATION) ||
            !runtime.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_ISOLATE_MAX_HEAP_SIZE)) {
            runtime.close()
            error("请更新 Android 系统 WebView 以启用脚本漫画源")
        }
        sandbox = runtime
        return runtime
    }

    private fun evaluate(code: String, queuedAt: Long, result: MethodChannel.Result) {
        try {
            if (System.nanoTime() - queuedAt > TimeUnit.SECONDS.toNanos(5)) {
                throw TimeoutException()
            }
            val parameters = IsolateStartupParameters().apply {
                setMaxHeapSizeBytes(16L * 1024 * 1024)
                setMaxEvaluationReturnSizeBytes(128 * 1024)
            }
            val isolate = runtime().createIsolate(parameters)
            val value = try {
                isolate.evaluateJavaScriptAsync(code).get(1500, TimeUnit.MILLISECONDS)
            } finally {
                runCatching { isolate.close() }
            }
            result.success(value)
        } catch (_: TimeoutException) {
            result.error("timeout", "脚本执行超时，已停止本次任务", null)
        } catch (error: Exception) {
            // Memory exhaustion or a WebView restart can kill the sandbox.
            // Reconnect on the next call. Return only bounded script diagnostics.
            runCatching { sandbox?.close() }
            sandbox = null
            result.error("script", (error.cause?.message ?: error.message ?: "脚本执行失败").take(400), null)
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.queue.clear()
        worker.execute {
            runCatching { sandbox?.close() }
            sandbox = null
        }
        worker.shutdown()
    }
}
