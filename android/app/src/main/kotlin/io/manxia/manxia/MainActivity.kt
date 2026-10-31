package io.manxia.manxia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.view.KeyEvent
import android.os.Build
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        // Flutter 3.47 GLES can terminate Linux x86 software emulators.
        // https://github.com/flutter/flutter/issues/192736
        // Retain hardware rendering defaults on physical devices.
        val x86 = Build.SUPPORTED_ABIS.any { it == "x86" || it == "x86_64" }
        val avd = Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish"
        if (x86 && avd) {
            args.remove(FlutterShellArgs.ARG_ENABLE_IMPELLER)
            args.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        }
        return args
    }

    private var volumeKeys = false
    private var channel: MethodChannel? = null
    private var updates: AppUpdateInstaller? = null
    private var reminders: MethodChannel? = null
    private var networkMonitor: NetworkMonitor? = null
    private var reminderPermission: Pair<Map<*, *>, MethodChannel.Result>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        networkMonitor = NetworkMonitor(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.manxia/network").setMethodCallHandler { call, result ->
            if (call.method == "state") result.success(networkMonitor?.state()) else result.notImplemented()
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "io.manxia/network-events").setStreamHandler(networkMonitor)
        reminders = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.manxia/follow-reminder")
        reminders?.setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(FollowReminders.config(this))
                "takeOpen" -> {
                    result.success(intent.getBooleanExtra("followCalendar", false))
                    intent.removeExtra("followCalendar")
                }
                "configure" -> {
                    val values = call.arguments as? Map<*, *>
                    if (values == null) {
                        result.error("arguments", "Invalid reminder configuration", null)
                    } else if (reminderPermission != null) {
                        result.error("busy", "Notification permission request is pending", null)
                    } else if (values["enabled"] == true && Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        reminderPermission = values to result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 40501)
                    } else {
                        saveReminder(values, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        try { FollowReminders.schedule(this) } catch (error: Exception) {
            android.util.Log.w("Manxia", "Unable to restore follow reminder", error)
        }
        updates = AppUpdateInstaller(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.manxia/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> {
                    val installedAbi = when (applicationInfo.nativeLibraryDir.substringAfterLast('/')) {
                        "arm64" -> "arm64-v8a"
                        "arm" -> "armeabi-v7a"
                        "x86_64" -> "x86_64"
                        else -> null
                    }
                    val abis = Build.SUPPORTED_ABIS.toList()
                    result.success(mapOf("abis" to if (installedAbi in abis) listOf(installedAbi) + abis.filter { it != installedAbi } else abis))
                }
                "install" -> updates?.install(call.argument<String>("path") ?: "", result)
                else -> result.notImplemented()
            }
        }
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
    override fun onDestroy() {
        networkMonitor?.close()
        reminderPermission?.second?.error("closed", "Activity closed before permission completed", null)
        reminderPermission = null
        updates?.close()
        super.onDestroy()
    }
    private fun saveReminder(values: Map<*, *>, result: MethodChannel.Result) {
        try {
            FollowReminders.configure(this, values)
            result.success(FollowReminders.config(this))
        } catch (error: Exception) {
            result.error("reminder", error.message, null)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 40501) {
            val pending = reminderPermission
            reminderPermission = null
            if (pending != null) saveReminder(pending.first, pending.second)
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("followCalendar", false)) {
            reminders?.invokeMethod("openCalendar", null)
        }
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeys && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }
}
