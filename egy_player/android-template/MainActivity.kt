package com.egyshow.player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: MethodChannel? = null
    private var picker: MethodChannel.Result? = null
    private val pickRequest = 9021

    private fun incomingLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return when (uri.scheme) {
            "egyplayer", "https" -> uri.toString()
            "content" -> if (intent.type?.startsWith("video/") == true) uri.toString() else null
            else -> null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.egyshow.player/launch")
        bridge?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialLink" -> result.success(incomingLink(intent))
                "pickVideo" -> {
                    if (picker != null) {
                        result.error("PICKER_BUSY", "Video picker is already open", null)
                    } else {
                        picker = result
                        try {
                            val request = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "video/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivityForResult(request, pickRequest)
                        } catch (_: Exception) {
                            picker = null
                            result.error("PICK_FAILED", "Cannot open video picker", null)
                        }
                    }
                }
                "videoName" -> {
                    val uri = Uri.parse(call.arguments as? String ?: "")
                    if (uri.scheme != "content") {
                        result.success(null)
                    } else {
                        val name = try {
                            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                                if (it.moveToFirst()) it.getString(0) else null
                            }
                        } catch (_: Exception) { null }
                        result.success(name)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Android activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val callback = picker ?: return
        picker = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        callback.success(if (uri?.scheme == "content") uri.toString() else null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingLink(intent)?.let { bridge?.invokeMethod("open", it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        picker?.success(null)
        picker = null
        bridge?.setMethodCallHandler(null)
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
