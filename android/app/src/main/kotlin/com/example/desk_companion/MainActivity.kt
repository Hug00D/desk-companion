package com.example.desk_companion

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.annotation.NonNull
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Category
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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val channel = "com.example.desk_companion/cv_channel"
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var visionExecutor: ExecutorService

    private val poseOptions = PoseDetectorOptions.Builder()
        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
        .build()
    private val poseDetector = PoseDetection.getClient(poseOptions)

    private val faceLandmarkerDelegate = lazy {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("face_landmarker.task")
            .build()
        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .setOutputFaceBlendshapes(true)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        FaceLandmarker.createFromOptions(this, options)
    }
    private val faceLandmarker: FaceLandmarker by faceLandmarkerDelegate

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

                else -> result.notImplemented()
            }
        }
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        try {
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
                ?: throw IllegalArgumentException("Unable to decode image data")
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            val resultMap = mutableMapOf<String, Any>()

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

                    visionExecutor.execute {
                        analyzeFaceWithMediaPipe(bitmap, resultMap, result)
                    }
                }
                .addOnFailureListener { e ->
                    result.error("POSE_ERROR", e.message, null)
                }
        } catch (e: Exception) {
            result.error("PROCESS_ERROR", e.message, null)
        }
    }

    private fun analyzeFaceWithMediaPipe(
        bitmap: android.graphics.Bitmap,
        resultMap: MutableMap<String, Any>,
        result: MethodChannel.Result
    ) {
        try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val faceResult = faceLandmarker.detect(mpImage)

            if (faceResult.faceLandmarks().isNotEmpty()) {
                val landmarks = faceResult.faceLandmarks().first()
                val blendshapes = faceResult.faceBlendshapes()
                val firstFaceBlendshapes = if (blendshapes.isPresent) {
                    blendshapes.get().firstOrNull()
                } else {
                    null
                }

                resultMap["hasFace"] = true
                val leftBlendOpen = blendshapeOpenProbability(firstFaceBlendshapes, "eyeBlinkLeft")
                val rightBlendOpen = blendshapeOpenProbability(firstFaceBlendshapes, "eyeBlinkRight")
                val leftLandmarkOpen = landmarkOpenProbability(landmarks, LEFT_EYE_POINTS)
                val rightLandmarkOpen = landmarkOpenProbability(landmarks, RIGHT_EYE_POINTS)

                resultMap["leftEye"] = combineOpenProbability(leftBlendOpen, leftLandmarkOpen)
                resultMap["rightEye"] = combineOpenProbability(rightBlendOpen, rightLandmarkOpen)
            } else {
                resultMap["hasFace"] = false
            }

            mainHandler.post {
                result.success(resultMap)
            }
        } catch (e: Exception) {
            mainHandler.post {
                result.error("FACE_ERROR", e.message, null)
            }
        }
    }

    private fun blendshapeOpenProbability(blendshapes: List<Category>?, blinkCategoryName: String): Float {
        val blinkScore = blendshapes
            ?.firstOrNull { it.categoryName() == blinkCategoryName }
            ?.score()
            ?: return -1f

        return clamp01(1.0f - blinkScore)
    }

    private fun landmarkOpenProbability(landmarks: List<NormalizedLandmark>, points: IntArray): Float {
        val outerCorner = landmarks.getOrNull(points[0]) ?: return -1f
        val upperOuter = landmarks.getOrNull(points[1]) ?: return -1f
        val upperInner = landmarks.getOrNull(points[2]) ?: return -1f
        val innerCorner = landmarks.getOrNull(points[3]) ?: return -1f
        val lowerInner = landmarks.getOrNull(points[4]) ?: return -1f
        val lowerOuter = landmarks.getOrNull(points[5]) ?: return -1f

        val vertical = distance(upperOuter, lowerOuter) + distance(upperInner, lowerInner)
        val horizontal = 2.0f * distance(outerCorner, innerCorner)
        if (horizontal <= 0.0f) return -1f

        val eyeAspectRatio = vertical / horizontal
        return clamp01((eyeAspectRatio - CLOSED_EYE_EAR) / (OPEN_EYE_EAR - CLOSED_EYE_EAR))
    }

    private fun combineOpenProbability(blendshapeOpen: Float, landmarkOpen: Float): Float {
        if (blendshapeOpen < 0.0f) return landmarkOpen
        if (landmarkOpen < 0.0f) return blendshapeOpen

        return min(blendshapeOpen, landmarkOpen)
    }

    private fun distance(a: NormalizedLandmark, b: NormalizedLandmark): Float {
        val dx = a.x() - b.x()
        val dy = a.y() - b.y()
        return sqrt(dx * dx + dy * dy)
    }

    private fun clamp01(value: Float): Float = max(0.0f, min(1.0f, value))

    override fun onDestroy() {
        super.onDestroy()
        poseDetector.close()
        if (faceLandmarkerDelegate.isInitialized()) {
            faceLandmarker.close()
        }
        if (::visionExecutor.isInitialized) {
            visionExecutor.shutdown()
        }
    }

    companion object {
        private val LEFT_EYE_POINTS = intArrayOf(362, 385, 387, 263, 373, 380)
        private val RIGHT_EYE_POINTS = intArrayOf(33, 160, 158, 133, 153, 144)
        private const val CLOSED_EYE_EAR = 0.13f
        private const val OPEN_EYE_EAR = 0.27f
    }
}
