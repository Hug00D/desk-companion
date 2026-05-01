package com.example.desk_companion

import android.graphics.BitmapFactory
import android.graphics.PointF
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.desk_companion/cv_channel"
    private lateinit var cameraExecutor: ExecutorService

    // Face Detector：保留 ML Kit 作為影像來源，但啟用 eye contours 來測試 EAR。
    private val faceDetectorOptions = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
        .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
        .build()
    private val faceDetector = FaceDetection.getClient(faceDetectorOptions)

    // Pose Detector：暫時保留原本肩膀/坐姿邏輯。
    private val poseOptions = PoseDetectorOptions.Builder()
        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
        .build()
    private val poseDetector = PoseDetection.getClient(poseOptions)

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

                "analyzeFrame" -> {
                    val imageData = call.arguments as? ByteArray
                    if (imageData != null) {
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

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        try {
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            if (bitmap == null) {
                result.error("DECODE_ERROR", "無法解析影像資料", null)
                return
            }

            val image = InputImage.fromBitmap(bitmap, 0)
            val resultMap = mutableMapOf<String, Any>()

            // 1. Pose 偵測：抓左右肩座標。
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

                    // 2. Face 偵測：除了 ML Kit 眼睛開度，也回傳 EAR 測試值。
                    faceDetector.process(image)
                        .addOnSuccessListener { faces ->
                            if (faces.isNotEmpty()) {
                                val face = faces[0]
                                val leftEyeProbability = face.leftEyeOpenProbability ?: -1f
                                val rightEyeProbability = face.rightEyeOpenProbability ?: -1f

                                val leftEyeContour = face.getContour(FaceContour.LEFT_EYE)?.points
                                val rightEyeContour = face.getContour(FaceContour.RIGHT_EYE)?.points
                                val leftEar = calculateEyeAspectRatio(leftEyeContour)
                                val rightEar = calculateEyeAspectRatio(rightEyeContour)

                                resultMap["hasFace"] = true
                                resultMap["eyeMetricMode"] = if (leftEar > 0f && rightEar > 0f) {
                                    "EAR"
                                } else {
                                    "MLKIT_PROBABILITY_FALLBACK"
                                }

                                // 新欄位：EAR 測試值。
                                resultMap["leftEAR"] = leftEar
                                resultMap["rightEAR"] = rightEar

                                // 舊欄位：保留 ML Kit probability，避免 Flutter 端舊功能完全斷裂。
                                resultMap["leftEyeProbability"] = leftEyeProbability
                                resultMap["rightEyeProbability"] = rightEyeProbability
                                resultMap["leftEye"] = leftEyeProbability
                                resultMap["rightEye"] = rightEyeProbability
                            } else {
                                resultMap["hasFace"] = false
                                resultMap["eyeMetricMode"] = "NO_FACE"
                            }

                            result.success(resultMap)
                        }
                        .addOnFailureListener { e ->
                            result.error("FACE_ERROR", e.message, null)
                        }
                }
                .addOnFailureListener { e ->
                    result.error("POSE_ERROR", e.message, null)
                }
        } catch (e: Exception) {
            result.error("PROCESS_ERROR", e.message, null)
        }
    }

    /**
     * EAR 測試版：
     * 這裡先用 eye contour 的 bounding box 高寬比作為簡化 EAR。
     * 真正 MediaPipe Face Landmarker 版本之後可以替換成指定眼部 landmark 的六點 EAR。
     */
    private fun calculateEyeAspectRatio(points: List<PointF>?): Float {
        if (points == null || points.size < 4) return -1f

        var minX = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        var maxY = -Float.MAX_VALUE

        for (point in points) {
            if (point.x < minX) minX = point.x
            if (point.x > maxX) maxX = point.x
            if (point.y < minY) minY = point.y
            if (point.y > maxY) maxY = point.y
        }

        val width = maxX - minX
        val height = maxY - minY

        if (width <= 0f || height <= 0f) return -1f
        return height / width
    }

    override fun onDestroy() {
        super.onDestroy()
        faceDetector.close()
        poseDetector.close()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }
}
