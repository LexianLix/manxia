package io.manxia.manxia

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class AppUpdateInstaller(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    fun close() = worker.shutdownNow()
    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> {
        val values = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return values?.map { MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).joinToString("") { b -> "%02x".format(b) } }?.toSet() ?: emptySet()
    }
    @Suppress("DEPRECATION")
    fun install(path: String, result: MethodChannel.Result) {
        worker.execute {
            try {
                val directory = File(activity.cacheDir, "updates").canonicalFile
                val file = File(path).canonicalFile
                require(file.parentFile == directory && file.isFile && file.extension == "apk") { "Invalid update path" }
                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
                val candidate = activity.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("Invalid APK")
                require(candidate.packageName == activity.packageName) { "Package does not match" }
                val existingSigners = signatures(installed)
                require(existingSigners.isNotEmpty() && signatures(candidate) == existingSigners) { "Signing certificate does not match" }
                val currentCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                val nextCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
                require(nextCode > currentCode) { "Update must be newer than installed app" }
                activity.runOnUiThread {
                    try {
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                            result.success("permission")
                        } else {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success("installer")
                        }
                    } catch (_: Exception) { result.error("INSTALL_UNAVAILABLE", "无法打开系统安装器，请到发行页下载后覆盖安装。", null) }
                }
            } catch (_: Exception) {
                activity.runOnUiThread { result.error("INVALID_UPDATE", "安装包校验未通过：请确认是更高版本、相同签名的漫匣发行包。", null) }
            }
        }
    }
}
