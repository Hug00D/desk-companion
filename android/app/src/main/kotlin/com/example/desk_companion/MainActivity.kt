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

    // Pose Detector：目前先保留 ML Kit Pose，避免 Face / Pose 一次全換造成除錯困難。
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
            val assetSize = assets.open(faceModelAssetPath).use { it.available() }
            if (assetSize <= 0) {
                throw IllegalStateException("$faceModelAssetPath 存在，但檔案大小為 0，請重新下載正確的 MediaPipe task 模型。")
            }

            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(faceModelAssetPath)
                .build()

            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinFacePresenceConfidence(0.5f)
                .build()

            faceLandmarker = FaceLandmarker.createFromOptions(this, options)
            faceLandmarkerInitError = null
        } catch (t: Throwable) {
            faceLandmarker = null
            faceLandmarkerInitError = buildMediaPipeInitError(t)
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

            // 先跑 Face EAR。即使 Pose 失敗，也不要阻斷疲勞偵測。
            appendFaceResult(bitmap, resultMap)

            // Pose 只是坐姿輔助資料；失敗時回傳 poseError，Flutter 仍可顯示 EAR。
            poseDetector.process(inputImage)
                .addOnSuccessListener { pose ->
                    appendPoseResult(pose, resultMap)
                    result.success(resultMap)
                }
                .addOnFailureListener { e ->
                    resultMap["hasPose"] = false
                    resultMap["poseError"] = "${e::class.java.simpleName}: ${e.message ?: e.toString()}"
                    result.success(resultMap)
                }
        } catch (t: Throwable) {
            result.error("PROCESS_ERROR", "${t::class.java.simpleName}: ${t.message ?: t.toString()}", null)
        }
    }

    private fun appendFaceResult(
        bitmap: android.graphics.Bitmap,
        resultMap: MutableMap<String, Any>
    ) {
        val landmarker = faceLandmarker
        if (landmarker == null) {
            resultMap["hasFace"] = false
            resultMap["eyeMetricMode"] = "MEDIAPIPE_MODEL_NOT_READY"
            resultMap["mediaPipeError"] = faceLandmarkerInitError ?: "FaceLandmarker 尚未初始化"
            return
        }

        try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val faceResult = landmarker.detect(mpImage)
            val faceLandmarks = faceResult.faceLandmarks()

            if (faceLandmarks.isNotEmpty()) {
                val landmarks = faceLandmarks[0]
                val leftEar = calculateMediaPipeEar(landmarks, LEFT_EYE_INDICES)
                val rightEar = calculateMediaPipeEar(landmarks, RIGHT_EYE_INDICES)

                resultMap["hasFace"] = leftEar > 0f && rightEar > 0f
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
        } catch (t: Throwable) {
            resultMap["hasFace"] = false
            resultMap["eyeMetricMode"] = "MEDIAPIPE_RUNTIME_ERROR"
            resultMap["mediaPipeError"] = "${t::class.java.simpleName}: ${t.message ?: t.toString()}"
        }
    }

    private fun appendPoseResult(
        pose: com.google.mlkit.vision.pose.Pose,
        resultMap: MutableMap<String, Any>
    ) {
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
    }

    private fun buildMediaPipeInitError(t: Throwable): String {
        val rawMessage = "${t::class.java.simpleName}: ${t.message ?: t.toString()}"
        val isMissingNativeLibrary = t is UnsatisfiedLinkError || rawMessage.contains("libmediapipe_tasks_vision_jni.so")

        return if (isMissingNativeLibrary) {
            "$rawMessage。此裝置或模擬器無法載入 MediaPipe Tasks Vision native library。若你使用 sdk gphone64 x86_64 模擬器，請改用 ARM64 實機測試，或先使用 ML Kit fallback。"
        } else {
            rawMessage
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
