package com.geovannycode.corteya

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences("barbershop", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.geovannycode.corteya/preferences")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readSlug" -> result.success(preferences.getString("slug", null))
                    "writeSlug" -> {
                        val slug = call.arguments as? String
                        val editor = preferences.edit()
                        if (slug == null) editor.remove("slug") else editor.putString("slug", slug)
                        if (editor.commit()) result.success(null)
                        else result.error("storage", "No se pudo guardar la barbería", null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
