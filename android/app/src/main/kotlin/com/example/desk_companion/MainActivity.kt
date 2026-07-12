package com.example.desk_companion

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channel = "com.example.desk_companion/cv_channel"
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var visionExecutor: ExecutorService
    private var frameCounter = 0L
    private val visionManagerDelegate = lazy {
        MediaPipeVisionManager(this)
    }
    private val visionManager: MediaPipeVisionManager by visionManagerDelegate

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        visionExecutor = Executors.newSingleThreadExecutor()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "showToast" -> {
                    val message = call.argument<String>("message")
                    Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                    result.success("OK")
                }

                "analyzeFrame" -> {
                    val imageData = call.arguments as? ByteArray
                    if (imageData != null) {
                        processImage(imageData, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Image data is required", null)
                    }
                }

                "startCamera" -> {
                    result.success("Simulator Mode: Camera logic bypassed")
                }

                "resetVision" -> {
                    frameCounter = 0L
                    if (visionManagerDelegate.isInitialized()) {
                        visionManager.resetCalibration()
                    }
                    result.success("OK")
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        visionExecutor.execute {
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            try {
                if (bitmap == null) {
                    throw IllegalArgumentException("Unable to decode image data")
                }
                frameCounter++

                val resultMap = visionManager.analyze(
                    bitmap = bitmap,
                    runFace = shouldRun(frameCounter, FACE_DETECTION_INTERVAL),
                    runPose = shouldRun(frameCounter, POSE_DETECTION_INTERVAL)
                )

                mainHandler.post {
                    result.success(resultMap)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("PROCESS_ERROR", e.message, null)
                }
            } finally {
                bitmap?.recycle()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (visionManagerDelegate.isInitialized()) {
            visionManager.close()
        }
        if (::visionExecutor.isInitialized) {
            visionExecutor.shutdown()
        }
    }

    private fun shouldRun(frameNumber: Long, interval: Int): Boolean {
        return (frameNumber - 1L) % interval == 0L
    }

    companion object {
        private const val FACE_DETECTION_INTERVAL = 1
        // Flutter currently submits a still image about every 800 ms, so each
        // submitted image must produce a fresh pose result.
        private const val POSE_DETECTION_INTERVAL = 1
    }
}
