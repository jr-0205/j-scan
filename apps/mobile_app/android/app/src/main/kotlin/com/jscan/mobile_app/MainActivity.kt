package com.jscan.mobile_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingText: String? = null
    private val pendingFiles = mutableListOf<String>()
    private var transferServiceRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "jscan/share",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialText" -> {
                        result.success(pendingText)
                        pendingText = null
                    }
                    "getInitialFiles" -> {
                        result.success(ArrayList(pendingFiles))
                        pendingFiles.clear()
                    }
                    "copyToCache" -> {
                        val uri = call.arguments as? String
                        result.success(
                            uri?.let { importToCache(Uri.parse(it)) },
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "jscan/foreground",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title")
                        ?: "Enviando archivos a la PC"
                    val progress = call.argument<Int>("progress") ?: 0
                    startTransferService(title, progress, foreground = true)
                    transferServiceRunning = true
                    result.success(null)
                }
                "update" -> {
                    val title = call.argument<String>("title")
                        ?: "Enviando archivos a la PC"
                    val progress = call.argument<Int>("progress") ?: 0
                    startTransferService(
                        title,
                        progress,
                        foreground = !transferServiceRunning,
                    )
                    transferServiceRunning = true
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, FileTransferService::class.java))
                    transferServiceRunning = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }

        val type = intent.type ?: return
        if (type.startsWith("text/")) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            if (text.isBlank()) return
            intent.action = null
            val channel = shareChannel
            if (channel != null) {
                channel.invokeMethod("sharedText", text)
            } else {
                pendingText = text
            }
            return
        }

        val uris = mutableListOf<Uri>()
        @Suppress("DEPRECATION")
        if (action == Intent.ACTION_SEND) {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(
                uris::addAll,
            )
        }
        if (uris.isEmpty()) return

        // Evita reprocesar el mismo intent si la actividad se recrea.
        intent.action = null
        val paths = uris.mapNotNull(::importToCache)
        if (paths.isEmpty()) return

        val channel = shareChannel
        if (channel != null) {
            channel.invokeMethod("sharedFiles", paths)
        } else {
            pendingFiles.addAll(paths)
        }
    }

    private fun importToCache(uri: Uri): String? {
        return try {
            if (uri.scheme == "file") {
                return uri.path?.takeIf { File(it).isFile }
            }
            val original = queryDisplayName(uri) ?: "archivo-${System.currentTimeMillis()}"
            val safe = original
                .replace(Regex("[^A-Za-z0-9._ -]"), "_")
                .trim()
                .take(120)
                .ifBlank { "archivo-${System.currentTimeMillis()}" }
            val directory = File(cacheDir, "jscan_shared").apply { mkdirs() }
            val target = uniqueFile(directory, safe)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output, 1 shl 20)
                }
            } ?: return null
            target.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            } ?: uri.lastPathSegment
        } catch (_: Exception) {
            uri.lastPathSegment
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (index < 1000) {
            candidate = File(directory, "$stem ($index)$extension")
            if (!candidate.exists()) return candidate
            index += 1
        }
        return File(directory, "$stem-${System.currentTimeMillis()}$extension")
    }

    private fun startTransferService(
        title: String,
        progress: Int,
        foreground: Boolean,
    ) {
        val intent = Intent(this, FileTransferService::class.java).apply {
            putExtra(FileTransferService.EXTRA_TITLE, title)
            putExtra(FileTransferService.EXTRA_PROGRESS, progress)
            putExtra(FileTransferService.EXTRA_HAS_PROGRESS, progress > 0)
        }
        if (foreground && Build.VERSION.SDK_INT >= 26) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }
}
