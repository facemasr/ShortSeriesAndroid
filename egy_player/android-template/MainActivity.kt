package com.egyshow.player

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.egyshow.player/launch")
        bridge?.setMethodCallHandler { call, result ->
            if (call.method == "initialLink") result.success(intent?.dataString)
            else result.notImplemented()
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bridge?.invokeMethod("open", intent.dataString)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.setMethodCallHandler(null)
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
