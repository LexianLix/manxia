package io.manxia.manxia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    private var volumeKeys = false
    private var channel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.manxia/device")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "volumeKeys" -> { volumeKeys = call.arguments == true; result.success(null) }
                "brightness" -> {
                    val value = (call.arguments as? Number)?.toFloat() ?: -1f
                    window.attributes = window.attributes.apply {
                        screenBrightness = if (value < 0) -1f else value.coerceIn(0.01f, 1f)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            channel?.invokeMethod("volume", if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) 1 else -1)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }
}
