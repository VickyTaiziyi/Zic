package dev.zic.remote

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // One-shot path for the Dart file store. Returns immediately — this
        // channel does not touch SharedPreferences, whose plugin can hang
        // and drop the login into temporary mode.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.zic.remote/store")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "filesDir" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep the latest deep-link intent so app_links / home_widget see it.
        setIntent(intent)
    }
}
