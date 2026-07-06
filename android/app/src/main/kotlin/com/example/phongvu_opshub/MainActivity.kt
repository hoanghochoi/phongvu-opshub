package com.example.phongvu_opshub

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val mediaChannelName = "phongvu_opshub/media"
    private val updateChannelName = "phongvu_opshub/app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePngToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName") ?: "vietqr.png"
                    if (bytes == null) {
                        result.error("INVALID_BYTES", "Missing PNG bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = savePngToGallery(bytes, fileName)
                        result.success(uri)
                    } catch (error: Exception) {
                        result.error("SAVE_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Missing APK path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(File(path))
                        result.success(true)
                    } catch (error: UpdateInstallException) {
                        result.error(error.code, error.message, null)
                    } catch (error: Exception) {
                        result.error("INSTALL_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun savePngToGallery(bytes: ByteArray, fileName: String): String {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PhongVu OpsHub")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("Cannot create image file")
        resolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: error("Cannot open image file")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return uri.toString()
    }

    private fun installApk(file: File) {
        if (!file.exists() || file.length() <= 0) {
            throw UpdateInstallException("INVALID_APK", "Downloaded APK is missing")
        }

        validateApkForUpdate(file)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
            throw UpdateInstallException(
                "INSTALL_PERMISSION_REQUIRED",
                "Install permission is required"
            )
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(packageManager) == null) {
            throw UpdateInstallException("NO_INSTALLER", "No APK installer available")
        }
        startActivity(intent)
    }

    private fun validateApkForUpdate(file: File) {
        val flags = signingFlags()
        val archiveInfo = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw UpdateInstallException("INVALID_APK", "Cannot read APK metadata")
        if (archiveInfo.packageName != packageName) {
            throw UpdateInstallException("PACKAGE_MISMATCH", "APK package name mismatch")
        }

        val currentInfo = packageManager.getPackageInfo(packageName, flags)
        if (versionCodeOf(archiveInfo) <= versionCodeOf(currentInfo)) {
            throw UpdateInstallException("VERSION_NOT_NEWER", "APK version is not newer")
        }

        val currentSignatures = signatureDigests(currentInfo)
        val archiveSignatures = signatureDigests(archiveInfo)
        if (currentSignatures.isEmpty() || archiveSignatures.isEmpty()) {
            throw UpdateInstallException("SIGNATURE_MISSING", "APK signature is missing")
        }
        if (currentSignatures.intersect(archiveSignatures).isEmpty()) {
            throw UpdateInstallException("SIGNATURE_MISMATCH", "APK signature mismatch")
        }
    }

    private fun signingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
    }

    private fun versionCodeOf(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun signatureDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
        return signatures.map { sha256Hex(it.toByteArray()) }.toSet()
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private class UpdateInstallException(
        val code: String,
        override val message: String
    ) : Exception(message)
}
