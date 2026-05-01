package com.example.desk_companion

import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.annotation.NonNull
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.desk_companion/cv_channel"
    private val faceModelAssetPath = "face_landmarker.task"
    private lateinit var cameraExecutor: ExecutorService
    private var faceLandmarker: FaceLandmarker? = null
    private var faceLandmarkerInitError: String? = null

    // Pose Detector：Step 2 先保留 ML Kit Pose，避免 Face / Pose 一次全換造成除錯困難。
    private val poseOptions = PoseDetectorOptions.Builder()
        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
        .build()
    private val poseDetector = PoseDetection.getClient(poseOptions)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cameraExecutor = Executors.newSingleThreadExecutor()
        initializeFaceLandmarker()

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

    private fun initializeFaceLandmarker() {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(faceModelAssetPath)
                .build()

            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()

            faceLandmarker = FaceLandmarker.createFromOptions(this, options)
            faceLandmarkerInitError = null
        } catch (e: Exception) {
            faceLandmarker = null
            faceLandmarkerInitError = e.message ?: e.toString()
        }
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        try {
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            if (bitmap == null) {
                result.error("DECODE_ERROR", "無法解析影像資料", null)
                return
            }

            val inputImage = InputImage.fromBitmap(bitmap, 0)
            val resultMap = mutableMapOf<String, Any>()

            // 1. Pose 偵測：目前先保留 ML Kit Pose，維持肩寬 / 坐姿資料。
            poseDetector.process(inputImage)
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

                    // 2. Face 偵測：改用 MediaPipe Face Landmarker 取得 landmarks，再計算六點 EAR。
                    val landmarker = faceLandmarker
                    if (landmarker == null) {
                        resultMap["hasFace"] = false
                        resultMap["eyeMetricMode"] = "MEDIAPIPE_MODEL_NOT_READY"
                        resultMap["mediaPipeError"] = faceLandmarkerInitError ?: "FaceLandmarker 尚未初始化"
                        result.success(resultMap)
                        return@addOnSuccessListener
                    }

                    try {
                        val mpImage = BitmapImageBuilder(bitmap).build()
                        val faceResult = landmarker.detect(mpImage)
                        val faceLandmarks = faceResult.faceLandmarks()

                        if (faceLandmarks.isNotEmpty()) {
                            val landmarks = faceLandmarks[0]
                            val leftEar = calculateMediaPipeEar(landmarks, LEFT_EYE_INDICES)
                            val rightEar = calculateMediaPipeEar(landmarks, RIGHT_EYE_INDICES)

                            resultMap["hasFace"] = true
                            resultMap["eyeMetricMode"] = "MEDIAPIPE_EAR"
                            resultMap["leftEAR"] = leftEar
                            resultMap["rightEAR"] = rightEar

                            // 保留 Flutter 端既有欄位名稱，讓 Dart 端不需要大改。
                            resultMap["leftEye"] = leftEar
                            resultMap["rightEye"] = rightEar
                            resultMap["leftEyeProbability"] = -1f
                            resultMap["rightEyeProbability"] = -1f
                        } else {
                            resultMap["hasFace"] = false
                            resultMap["eyeMetricMode"] = "MEDIAPIPE_NO_FACE"
                        }

                        result.success(resultMap)
                    } catch (e: Exception) {
                        resultMap["hasFace"] = false
                        resultMap["eyeMetricMode"] = "MEDIAPIPE_RUNTIME_ERROR"
                        resultMap["mediaPipeError"] = e.message ?: e.toString()
                        result.success(resultMap)
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
     * MediaPipe Face Landmarker 六點 EAR。
     * EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
     */
    private fun calculateMediaPipeEar(
        landmarks: List<NormalizedLandmark>,
        indices: IntArray
    ): Float {
        if (indices.size != 6) return -1f
        if (indices.any { it < 0 || it >= landmarks.size }) return -1f

        val p1 = landmarks[indices[0]]
        val p2 = landmarks[indices[1]]
        val p3 = landmarks[indices[2]]
        val p4 = landmarks[indices[3]]
        val p5 = landmarks[indices[4]]
        val p6 = landmarks[indices[5]]

        val horizontal = distance(p1.x(), p1.y(), p4.x(), p4.y())
        if (horizontal <= 0f) return -1f

        val verticalA = distance(p2.x(), p2.y(), p6.x(), p6.y())
        val verticalB = distance(p3.x(), p3.y(), p5.x(), p5.y())

        return (verticalA + verticalB) / (2f * horizontal)
    }

    private fun distance(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x1 - x2
        val dy = y1 - y2
        return sqrt(dx * dx + dy * dy)
    }

    override fun onDestroy() {
        super.onDestroy()
        faceLandmarker?.close()
        poseDetector.close()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }

    companion object {
        // MediaPipe Face Mesh 常用眼睛六點 landmark index。
        private val RIGHT_EYE_INDICES = intArrayOf(33, 160, 158, 133, 153, 144)
        private val LEFT_EYE_INDICES = intArrayOf(362, 385, 387, 263, 373, 380)
    }
}
