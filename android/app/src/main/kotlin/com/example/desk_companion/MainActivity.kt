package com.example.desk_companion

import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.desk_companion/cv_channel"
    private lateinit var cameraExecutor: ExecutorService

    // --- Face Detector 配置 ---
    private val faceDetectorOptions = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .build()
    private val faceDetector = FaceDetection.getClient(faceDetectorOptions)

    // --- Pose Detector 配置 ---
    private val poseOptions = PoseDetectorOptions.Builder()
        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
        .build()
    private val poseDetector = PoseDetection.getClient(poseOptions)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine){
        super.configureFlutterEngine(flutterEngine)
        cameraExecutor = Executors.newSingleThreadExecutor()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when(call.method) {
                "showToast" -> {
                    val message = call.argument<String>("message")
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
            val resultMap = mutableMapOf<String, Any>()

            // 1. 先啟動 Pose 偵測 (抓肩膀)
            poseDetector.process(image)
                .addOnSuccessListener { pose ->
                    val leftShoulder = pose.getPoseLandmark(PoseLandmark.LEFT_SHOULDER)
                    val rightShoulder = pose.getPoseLandmark(PoseLandmark.RIGHT_SHOULDER)

                    if (leftShoulder != null && rightShoulder != null) {
                        resultMap["hasPose"] = true
                        resultMap["lsX"] = leftShoulder.position.x
                        resultMap["lsY"] = leftShoulder.position.y
                        resultMap["rsX"] = rightShoulder.position.x
                        resultMap["rsY"] = rightShoulder.position.y
                    } else {
                        resultMap["hasPose"] = false
                    }

                    // 2. 嵌套執行 Face 偵測 (抓眼睛)
                    faceDetector.process(image)
                        .addOnSuccessListener { faces ->
                            if(faces.isNotEmpty()){
                                val face = faces[0]
                                resultMap["hasFace"] = true
                                resultMap["leftEye"] = face.leftEyeOpenProbability ?: -1f
                                resultMap["rightEye"] = face.rightEyeOpenProbability ?: -1f
                            } else {
                                resultMap["hasFace"] = false
                            }
                            // 3. 兩邊都跑完了，一次回傳給 Flutter
                            result.success(resultMap)
                        }
                        .addOnFailureListener { e -> result.error("FACE_ERROR", e.message, null) }
                }
                .addOnFailureListener { e -> result.error("POSE_ERROR", e.message, null) }
        } catch (e: Exception) {
            result.error("PROCESS_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        faceDetector.close()
        poseDetector.close() // 釋放 Pose 資源
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }
}