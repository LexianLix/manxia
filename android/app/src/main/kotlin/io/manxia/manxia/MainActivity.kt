package io.manxia.manxia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel
import android.view.KeyEvent
import android.os.Build

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        // Flutter 3.47 GLES can terminate the old Linux software emulator.
        // Scope the fallback to the reproduced x86 AVD, retaining hardware
        // rendering defaults on real phones and newer Android versions.
        val x86 = Build.SUPPORTED_ABIS.any { it == "x86" || it == "x86_64" }
        val avd = Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish"
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R && x86 && avd) {
            args.remove(FlutterShellArgs.ARG_ENABLE_IMPELLER)
            args.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        }
        return args
    }

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
