package com.example.desk_buddy

import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.desk_buddy/cv_channel"
    private  lateinit var cameraExecutor: ExecutorService

    private val faceDetectorOptions = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .build()

    private val detector = FaceDetection.getClient(faceDetectorOptions)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine){
        super.configureFlutterEngine(flutterEngine)

        cameraExecutor = Executors.newSingleThreadExecutor()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when(call.method) {
                "showToast" -> {
                    val message = call.argument<String>("meaasge")
                    Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                    result.success("OK")
                }
                "analyzeFrame" -> {
                    val imageData = call.arguments as? ByteArray
                    if(imageData != null){
                        processImage(imageData, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "影像數據為空", null)
                    }
                }
                "startCamera" -> {
                    result.success("Simulator Mode: Camera logic bypassed")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result){
        try{
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            val image = InputImage.fromBitmap(bitmap, 0)

            detector.process(image)
                .addOnSuccessListener { faces ->
                    if(faces.isNotEmpty()){
                        val face = faces[0]
                        val leftEye = face.leftEyeOpenProbability ?: -1f
                        val rightEye = face.rightEyeOpenProbability ?: -1f

                        val resultMap = mapOf(
                            "hasFace" to true,
                            "leftEye" to leftEye,
                            "rightEye" to rightEye,
                            "faceCount" to faces.size
                        )
                        result.success(resultMap)
                    } else {
                        result.success(mapOf("hasFace" to false))
                    }
                }
                .addOnFailureListener { e ->
                    result.error("ML_KIT_ERROR", e.message, null)
                }
        } catch (e: Exception) {
            result.error("PROCESS_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        detector.close() // 釋放 AI 資源
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }
} // <-- 這裡才是結束 MainActivity 類別