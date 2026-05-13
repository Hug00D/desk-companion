package com.example.desk_companion

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Category
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MediaPipeVisionManager(context: Context) {
    private val faceLandmarker: FaceLandmarker
    private val poseLandmarker: PoseLandmarker
    private val handLandmarker: HandLandmarker
    private var lastFaceResult: Map<String, Any> = mapOf("hasFace" to false)
    private var lastPoseResult: Map<String, Any> = mapOf("hasPose" to false)
    private var lastHandResult: Map<String, Any> = mapOf("hasHand" to false)
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

        val handBaseOptions = BaseOptions.builder()
            .setModelAssetPath("hand_landmarker.task")
            .build()
        val handOptions = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(handBaseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumHands(1)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        handLandmarker = HandLandmarker.createFromOptions(context, handOptions)
    }

    fun analyze(bitmap: Bitmap, runFace: Boolean, runPose: Boolean, runHand: Boolean): Map<String, Any> {
        val resultMap = mutableMapOf<String, Any>()

        if (runFace || runPose || runHand) {
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

                if (runHand) {
                    lastHandResult = analyzeHand(mpImage)
                }
            } finally {
                mpImage.close()
            }
        }

        resultMap.putAll(lastPoseResult)
        resultMap.putAll(lastFaceResult)
        resultMap.putAll(lastHandResult)

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

    private fun analyzeHand(
        mpImage: com.google.mediapipe.framework.image.MPImage
    ): Map<String, Any> {
        val handResult = handLandmarker.detect(mpImage)
        val landmarks = handResult.landmarks().firstOrNull()

        return if (landmarks != null) {
            val isVictory = isVictoryGesture(landmarks)
            mapOf(
                "hasHand" to true,
                "handGesture" to if (isVictory) GESTURE_VICTORY else GESTURE_NONE,
                "isVictoryGesture" to isVictory
            )
        } else {
            mapOf(
                "hasHand" to false,
                "handGesture" to GESTURE_NONE,
                "isVictoryGesture" to false
            )
        }
    }

    private fun isVictoryGesture(landmarks: List<NormalizedLandmark>): Boolean {
        val wrist = landmarks.getOrNull(WRIST) ?: return false
        val indexMcp = landmarks.getOrNull(INDEX_MCP) ?: return false
        val indexPip = landmarks.getOrNull(INDEX_PIP) ?: return false
        val indexTip = landmarks.getOrNull(INDEX_TIP) ?: return false
        val middleMcp = landmarks.getOrNull(MIDDLE_MCP) ?: return false
        val middlePip = landmarks.getOrNull(MIDDLE_PIP) ?: return false
        val middleTip = landmarks.getOrNull(MIDDLE_TIP) ?: return false
        val ringPip = landmarks.getOrNull(RING_PIP) ?: return false
        val ringTip = landmarks.getOrNull(RING_TIP) ?: return false
        val pinkyMcp = landmarks.getOrNull(PINKY_MCP) ?: return false
        val pinkyPip = landmarks.getOrNull(PINKY_PIP) ?: return false
        val pinkyTip = landmarks.getOrNull(PINKY_TIP) ?: return false

        val palmWidth = distance(indexMcp, pinkyMcp)
        val handHeight = distance(wrist, middleMcp)
        val scale = max(0.05f, max(palmWidth, handHeight))

        val indexExtended = fingerTipAboveJoint(indexTip, indexPip, scale)
        val middleExtended = fingerTipAboveJoint(middleTip, middlePip, scale)
        val ringFolded = !fingerTipAboveJoint(ringTip, ringPip, scale * 0.8f)
        val pinkyFolded = !fingerTipAboveJoint(pinkyTip, pinkyPip, scale * 0.8f)
        val fingersSeparated = distance(indexTip, middleTip) > palmWidth * 0.35f
        val fingertipsAtSimilarHeight = abs(indexTip.y() - middleTip.y()) < scale * 0.75f

        return indexExtended &&
            middleExtended &&
            ringFolded &&
            pinkyFolded &&
            fingersSeparated &&
            fingertipsAtSimilarHeight
    }

    private fun fingerTipAboveJoint(
        tip: NormalizedLandmark,
        joint: NormalizedLandmark,
        scale: Float
    ): Boolean {
        return tip.y() < joint.y() - scale * 0.18f
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
        handLandmarker.close()
    }

    companion object {
        private const val GESTURE_NONE = "none"
        private const val GESTURE_VICTORY = "victory"
        private const val LEFT_SHOULDER = 11
        private const val RIGHT_SHOULDER = 12
        private const val WRIST = 0
        private const val INDEX_MCP = 5
        private const val INDEX_PIP = 6
        private const val INDEX_TIP = 8
        private const val MIDDLE_MCP = 9
        private const val MIDDLE_PIP = 10
        private const val MIDDLE_TIP = 12
        private const val RING_PIP = 14
        private const val RING_TIP = 16
        private const val PINKY_MCP = 17
        private const val PINKY_PIP = 18
        private const val PINKY_TIP = 20
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
