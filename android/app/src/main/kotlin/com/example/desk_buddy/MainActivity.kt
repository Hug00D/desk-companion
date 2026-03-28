package com.example.desk_buddy

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.desk_buddy/cv_channel"

    // 雖然現在是模擬模式，但建議保留 Executor 以便未來擴充
    private lateinit var cameraExecutor: ExecutorService

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cameraExecutor = Executors.newSingleThreadExecutor()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showToast" -> {
                    val message = call.argument<String>("message")
                    Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                    result.success("OK")
                }
                "startCamera" -> {
                    // 模擬模式：直接回傳成功，讓 Flutter 端的影片邏輯可以繼續跑
                    result.success("Simulator Mode: Camera logic bypassed")
                }
                "analyzeFrame" -> {
                    // 未來這裡會接收來自影片的 bytes 進行辨識
                    result.success("Analyzing frame via Video...")
                }
                else -> result.notImplemented()
            }
        }
    } // <-- 這裡結束 configureFlutterEngine

    private fun allPermissionsGranted() = REQUIRED_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(baseContext, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }

    companion object {
        private const val REQUEST_CODE_PERMISSIONS = 10
        private val REQUIRED_PERMISSIONS = arrayOf(Manifest.permission.CAMERA)
    }
} // <-- 這裡才是結束 MainActivity 類別