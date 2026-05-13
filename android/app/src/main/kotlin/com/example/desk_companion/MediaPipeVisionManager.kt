package com.example.desk_companion

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Category
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MediaPipeVisionManager(context: Context) {
    private val faceLandmarker: FaceLandmarker
    private val poseLandmarker: PoseLandmarker
    private var lastFaceResult: Map<String, Any> = mapOf("hasFace" to false)
    private var lastPoseResult: Map<String, Any> = mapOf("hasPose" to false)
    private var smoothedHeadYaw = 0.0f
    private var smoothedHeadPitch = 0.0f
    private var hasSmoothedHeadPose = false

    init {
        val faceBaseOptions = BaseOptions.builder()
            .setModelAssetPath("face_landmarker.task")
            .build()
        val faceOptions = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(faceBaseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .setOutputFaceBlendshapes(true)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        val poseBaseOptions = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_full.task")
            .build()
        val poseOptions = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(poseBaseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        faceLandmarker = FaceLandmarker.createFromOptions(context, faceOptions)
        poseLandmarker = PoseLandmarker.createFromOptions(context, poseOptions)
    }

    fun analyze(bitmap: Bitmap, runFace: Boolean, runPose: Boolean): Map<String, Any> {
        val resultMap = mutableMapOf<String, Any>()

        if (runFace || runPose) {
            val mpImage = BitmapImageBuilder(bitmap).build()
            try {
                if (runPose) {
                    lastPoseResult = analyzePose(
                        mpImage = mpImage,
                        imageWidth = bitmap.width,
                        imageHeight = bitmap.height
                    )
                }

                if (runFace) {
                    lastFaceResult = analyzeFace(mpImage)
                }
            } finally {
                mpImage.close()
            }
        }

        resultMap.putAll(lastPoseResult)
        resultMap.putAll(lastFaceResult)

        return resultMap
    }

    private fun analyzePose(
        mpImage: com.google.mediapipe.framework.image.MPImage,
        imageWidth: Int,
        imageHeight: Int
    ): Map<String, Any> {
        val poseResult = poseLandmarker.detect(mpImage)
        val landmarks = poseResult.landmarks().firstOrNull()
        val leftShoulder = landmarks?.getOrNull(LEFT_SHOULDER)
        val rightShoulder = landmarks?.getOrNull(RIGHT_SHOULDER)

        return if (leftShoulder != null && rightShoulder != null) {
            mapOf(
                "hasPose" to true,
                "lsX" to leftShoulder.x() * imageWidth,
                "lsY" to leftShoulder.y() * imageHeight,
                "rsX" to rightShoulder.x() * imageWidth,
                "rsY" to rightShoulder.y() * imageHeight
            )
        } else {
            mapOf("hasPose" to false)
        }
    }

    private fun analyzeFace(
        mpImage: com.google.mediapipe.framework.image.MPImage
    ): Map<String, Any> {
        val faceResult = faceLandmarker.detect(mpImage)

        return if (faceResult.faceLandmarks().isNotEmpty()) {
            val landmarks = faceResult.faceLandmarks().first()
            val blendshapes = faceResult.faceBlendshapes()
            val firstFaceBlendshapes = if (blendshapes.isPresent) {
                blendshapes.get().firstOrNull()
            } else {
                null
            }

            val leftBlendOpen = blendshapeOpenProbability(firstFaceBlendshapes, "eyeBlinkLeft")
            val rightBlendOpen = blendshapeOpenProbability(firstFaceBlendshapes, "eyeBlinkRight")
            val leftLandmarkOpen = landmarkOpenProbability(landmarks, LEFT_EYE_POINTS)
            val rightLandmarkOpen = landmarkOpenProbability(landmarks, RIGHT_EYE_POINTS)
            val headPose = estimateHeadPose(landmarks)

            mapOf(
                "hasFace" to true,
                "leftEye" to combineOpenProbability(leftBlendOpen, leftLandmarkOpen),
                "rightEye" to combineOpenProbability(rightBlendOpen, rightLandmarkOpen),
                "headYaw" to headPose.first,
                "headPitch" to headPose.second
            )
        } else {
            mapOf("hasFace" to false)
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

    private fun estimateHeadPose(landmarks: List<NormalizedLandmark>): Pair<Float, Float> {
        val nose = landmarks.getOrNull(NOSE_TIP)
        val leftEyeCorner = landmarks.getOrNull(LEFT_EYE_OUTER_CORNER)
        val rightEyeCorner = landmarks.getOrNull(RIGHT_EYE_OUTER_CORNER)
        val forehead = landmarks.getOrNull(FOREHEAD_TOP)
        val chin = landmarks.getOrNull(CHIN)

        if (nose == null || leftEyeCorner == null || rightEyeCorner == null || forehead == null || chin == null) {
            return smoothedHeadYaw to smoothedHeadPitch
        }

        val eyeWidth = distance(leftEyeCorner, rightEyeCorner)
        val faceHeight = distance(forehead, chin)
        if (eyeWidth <= 0.0f || faceHeight <= 0.0f) {
            return smoothedHeadYaw to smoothedHeadPitch
        }

        val eyeCenterX = (leftEyeCorner.x() + rightEyeCorner.x()) / 2.0f
        val rawYaw = clamp(
            value = ((nose.x() - eyeCenterX) / eyeWidth) * HEAD_YAW_SCALE,
            minValue = -MAX_HEAD_YAW,
            maxValue = MAX_HEAD_YAW
        )

        val normalizedNoseY = (nose.y() - forehead.y()) / (chin.y() - forehead.y())
        val rawPitch = clamp(
            value = (normalizedNoseY - NEUTRAL_NOSE_VERTICAL_RATIO) * HEAD_PITCH_SCALE,
            minValue = -MAX_HEAD_PITCH,
            maxValue = MAX_HEAD_PITCH
        )

        if (!hasSmoothedHeadPose) {
            smoothedHeadYaw = rawYaw
            smoothedHeadPitch = rawPitch
            hasSmoothedHeadPose = true
        } else {
            smoothedHeadYaw = smooth(smoothedHeadYaw, rawYaw)
            smoothedHeadPitch = smooth(smoothedHeadPitch, rawPitch)
        }

        return smoothedHeadYaw to smoothedHeadPitch
    }

    private fun smooth(previous: Float, current: Float): Float {
        return previous * HEAD_POSE_SMOOTHING + current * (1.0f - HEAD_POSE_SMOOTHING)
    }

    private fun distance(a: NormalizedLandmark, b: NormalizedLandmark): Float {
        val dx = a.x() - b.x()
        val dy = a.y() - b.y()
        return sqrt(dx * dx + dy * dy)
    }

    private fun clamp01(value: Float): Float = max(0.0f, min(1.0f, value))

    private fun clamp(value: Float, minValue: Float, maxValue: Float): Float {
        return max(minValue, min(maxValue, value))
    }

    fun close() {
        faceLandmarker.close()
        poseLandmarker.close()
    }

    companion object {
        private const val LEFT_SHOULDER = 11
        private const val RIGHT_SHOULDER = 12
        private const val NOSE_TIP = 1
        private const val FOREHEAD_TOP = 10
        private const val CHIN = 152
        private const val RIGHT_EYE_OUTER_CORNER = 33
        private const val LEFT_EYE_OUTER_CORNER = 263
        private val LEFT_EYE_POINTS = intArrayOf(362, 385, 387, 263, 373, 380)
        private val RIGHT_EYE_POINTS = intArrayOf(33, 160, 158, 133, 153, 144)
        private const val CLOSED_EYE_EAR = 0.13f
        private const val OPEN_EYE_EAR = 0.27f
        private const val HEAD_POSE_SMOOTHING = 0.75f
        private const val HEAD_YAW_SCALE = 80.0f
        private const val HEAD_PITCH_SCALE = 120.0f
        private const val MAX_HEAD_YAW = 45.0f
        private const val MAX_HEAD_PITCH = 45.0f
        private const val NEUTRAL_NOSE_VERTICAL_RATIO = 0.52f
    }
}
