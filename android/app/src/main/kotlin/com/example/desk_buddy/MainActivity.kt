package com.example.desk_buddy // 確保 package 名稱跟你的專案一致

import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.desk_buddy/cv_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "showToast") {
                val message = call.argument<String>("message")
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                result.success("Toast shown from Kotlin!")
            } else {
                result.notImplemented()
            }
        }
    }
}