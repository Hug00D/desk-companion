package com.example.desk_companion

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Category
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MediaPipeVisionManager(context: Context) {
    private val faceLandmarker: FaceLandmarker
    private val poseLandmarker: PoseLandmarker
    private var lastFaceResult: Map<String, Any> = mapOf("hasFace" to false)
    private var lastPoseResult: Map<String, Any> = mapOf("hasPose" to false)
    private var poseSequence = 0L
    private var smoothedHeadYaw = 0.0f
    private var smoothedHeadPitch = 0.0f
    private var headOffsetScore = 0.0f
    private var hasSmoothedHeadPose = false
    private var hasSmoothedHeadOffsetMetric = false
    private var headPitchBaseline: Float? = null
    private var smoothedHeadOffsetMetric = 0.0f
    private val headOffsetBaselineSamples = mutableListOf<Float>()
    private var headOffsetBaseline: Float? = null
    private var headOffsetScoreScale = HEAD_OFFSET_RATIO_SCORE_SCALE
    private var lastBaselineCandidateYaw: Float? = null
    private var headMatrixDebugCounter = 0L

    init {
        val faceBaseOptions = BaseOptions.builder()
            .setModelAssetPath("face_landmarker.task")
            .build()
        val faceOptions = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(faceBaseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumFaces(1)
            .setOutputFaceBlendshapes(true)
            .setOutputFacialTransformationMatrixes(true)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        val poseBaseOptions = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_lite.task")
            .build()
        val poseOptions = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(poseBaseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()

        faceLandmarker = FaceLandmarker.createFromOptions(context, faceOptions)
        poseLandmarker = PoseLandmarker.createFromOptions(context, poseOptions)
    }

    fun analyze(
        bitmap: Bitmap,
        runFace: Boolean,
        runPose: Boolean,
        timestampMs: Long
    ): Map<String, Any> {
        val resultMap = mutableMapOf<String, Any>()

        if (runFace || runPose) {
            val mpImage = BitmapImageBuilder(bitmap).build()
            try {
                if (runPose) {
                    lastPoseResult = analyzePose(
                        mpImage = mpImage,
                        imageWidth = bitmap.width,
                        imageHeight = bitmap.height,
                        timestampMs = timestampMs
                    )
                }

                if (runFace) {
                    lastFaceResult = analyzeFace(mpImage, timestampMs)
                }
            } finally {
                mpImage.close()
            }
        }

        resultMap.putAll(lastPoseResult)
        resultMap.putAll(lastFaceResult)

        return resultMap
    }

    fun shouldBoostPose(): Boolean {
        if (lastFaceResult["hasFace"] != true) return true
        val headOffset = lastFaceResult["headOffsetScore"] as? Number
        val headPitch = lastFaceResult["headPitch"] as? Number
        return (headOffset?.toFloat() ?: 0.0f) >= POSE_BOOST_HEAD_OFFSET ||
            abs(headPitch?.toFloat() ?: 0.0f) >= POSE_BOOST_HEAD_PITCH
    }

    private fun analyzePose(
        mpImage: com.google.mediapipe.framework.image.MPImage,
        imageWidth: Int,
        imageHeight: Int,
        timestampMs: Long
    ): Map<String, Any> {
        val poseResult = poseLandmarker.detectForVideo(mpImage, timestampMs)
        poseSequence++
        val landmarks = poseResult.landmarks().firstOrNull()
        val leftShoulder = landmarks?.getOrNull(LEFT_SHOULDER)
        val rightShoulder = landmarks?.getOrNull(RIGHT_SHOULDER)

        return if (leftShoulder != null && rightShoulder != null) {
            val result = mutableMapOf<String, Any>(
                "hasPose" to true,
                "poseSequence" to poseSequence,
                "imageWidth" to imageWidth,
                "imageHeight" to imageHeight,
                "lsX" to leftShoulder.x() * imageWidth,
                "lsY" to leftShoulder.y() * imageHeight,
                "lsVisibility" to landmarkVisibility(leftShoulder),
                "rsX" to rightShoulder.x() * imageWidth,
                "rsY" to rightShoulder.y() * imageHeight,
                "rsVisibility" to landmarkVisibility(rightShoulder)
            )
            addPoseLandmark(result, "poseNose", landmarks, POSE_NOSE, imageWidth, imageHeight)
            addPoseLandmark(result, "poseLeftEye", landmarks, POSE_LEFT_EYE, imageWidth, imageHeight)
            addPoseLandmark(result, "poseRightEye", landmarks, POSE_RIGHT_EYE, imageWidth, imageHeight)
            addPoseLandmark(result, "poseLeftEar", landmarks, POSE_LEFT_EAR, imageWidth, imageHeight)
            addPoseLandmark(result, "poseRightEar", landmarks, POSE_RIGHT_EAR, imageWidth, imageHeight)
            result
        } else {
            mapOf(
                "hasPose" to false,
                "poseSequence" to poseSequence,
                "imageWidth" to imageWidth,
                "imageHeight" to imageHeight
            )
        }
    }

    private fun addPoseLandmark(
        result: MutableMap<String, Any>,
        keyPrefix: String,
        landmarks: List<NormalizedLandmark>?,
        index: Int,
        imageWidth: Int,
        imageHeight: Int
    ) {
        val landmark = landmarks?.getOrNull(index) ?: return
        result["${keyPrefix}X"] = landmark.x() * imageWidth
        result["${keyPrefix}Y"] = landmark.y() * imageHeight
        result["${keyPrefix}Visibility"] = landmarkVisibility(landmark)
    }

    private fun landmarkVisibility(landmark: NormalizedLandmark): Float {
        return landmark.visibility().orElse(1.0f)
    }

    private fun analyzeFace(
        mpImage: com.google.mediapipe.framework.image.MPImage,
        timestampMs: Long
    ): Map<String, Any> {
        val faceResult = faceLandmarker.detectForVideo(mpImage, timestampMs)

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
            val leftEar = eyeAspectRatio(landmarks, LEFT_EYE_POINTS)
            val rightEar = eyeAspectRatio(landmarks, RIGHT_EYE_POINTS)
            val leftLandmarkOpen = landmarkOpenProbability(leftEar)
            val rightLandmarkOpen = landmarkOpenProbability(rightEar)
            val transformationMatrix = faceResult.facialTransformationMatrixes()
                .orElse(emptyList())
                .firstOrNull()
            val leftEyeOpen = combineOpenProbability(leftBlendOpen, leftLandmarkOpen)
            val rightEyeOpen = combineOpenProbability(rightBlendOpen, rightLandmarkOpen)
            val headPose = estimateHeadPose(
                landmarks = landmarks,
                transformationMatrix = transformationMatrix,
                leftEyeOpen = leftEyeOpen,
                rightEyeOpen = rightEyeOpen
            )

            mutableMapOf<String, Any>(
                "hasFace" to true,
                "leftEye" to leftEyeOpen,
                "rightEye" to rightEyeOpen,
                "headYaw" to headPose.first,
                "headPitch" to headPose.second,
                "headOffsetScore" to headPose.third,
                "headOffsetCalibrating" to (headOffsetBaseline == null)
            ).apply {
                if (leftEar >= 0.0f) put("leftEar", leftEar)
                if (rightEar >= 0.0f) put("rightEar", rightEar)
            }
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

    private fun eyeAspectRatio(landmarks: List<NormalizedLandmark>, points: IntArray): Float {
        val outerCorner = landmarks.getOrNull(points[0]) ?: return -1f
        val upperOuter = landmarks.getOrNull(points[1]) ?: return -1f
        val upperInner = landmarks.getOrNull(points[2]) ?: return -1f
        val innerCorner = landmarks.getOrNull(points[3]) ?: return -1f
        val lowerInner = landmarks.getOrNull(points[4]) ?: return -1f
        val lowerOuter = landmarks.getOrNull(points[5]) ?: return -1f

        val vertical = distance(upperOuter, lowerOuter) + distance(upperInner, lowerInner)
        val horizontal = 2.0f * distance(outerCorner, innerCorner)
        if (horizontal <= 0.0f) return -1f

        return vertical / horizontal
    }

    private fun landmarkOpenProbability(eyeAspectRatio: Float): Float {
        if (eyeAspectRatio < 0.0f) return -1f
        return clamp01((eyeAspectRatio - CLOSED_EYE_EAR) / (OPEN_EYE_EAR - CLOSED_EYE_EAR))
    }

    private fun combineOpenProbability(blendshapeOpen: Float, landmarkOpen: Float): Float {
        if (blendshapeOpen < 0.0f) return landmarkOpen
        if (landmarkOpen < 0.0f) return blendshapeOpen

        return min(blendshapeOpen, landmarkOpen)
    }

    private fun estimateHeadPose(
        landmarks: List<NormalizedLandmark>,
        transformationMatrix: FloatArray?,
        leftEyeOpen: Float,
        rightEyeOpen: Float
    ): Triple<Float, Float, Float> {
        val nose = landmarks.getOrNull(NOSE_TIP)
        val leftEyeCorner = landmarks.getOrNull(LEFT_EYE_OUTER_CORNER)
        val rightEyeCorner = landmarks.getOrNull(RIGHT_EYE_OUTER_CORNER)
        val forehead = landmarks.getOrNull(FOREHEAD_TOP)
        val chin = landmarks.getOrNull(CHIN)

        if (nose == null || leftEyeCorner == null || rightEyeCorner == null || forehead == null || chin == null) {
            return Triple(smoothedHeadYaw, smoothedHeadPitch, headOffsetScore)
        }

        val eyeWidth = distance(leftEyeCorner, rightEyeCorner)
        val faceHeight = distance(forehead, chin)
        if (eyeWidth <= 0.0f || faceHeight <= 0.0f) {
            return Triple(smoothedHeadYaw, smoothedHeadPitch, headOffsetScore)
        }

        val distToLeft = abs(nose.x() - leftEyeCorner.x())
        val distToRight = abs(nose.x() - rightEyeCorner.x())
        val eyeDistanceSum = distToLeft + distToRight
        if (eyeDistanceSum <= 0.0f) {
            return Triple(smoothedHeadYaw, smoothedHeadPitch, headOffsetScore)
        }
        val yawRatio = (distToLeft - distToRight) / eyeDistanceSum
        transformationMatrix?.let { logHeadMatrixDebug(it) }
        val matrixYaw = transformationMatrix?.let { extractYawFromMatrix(it) }
        val matrixPitch = transformationMatrix?.let { extractPitchFromMatrix(it) }
        val yawMetric = matrixYaw ?: yawRatio
        val scoreScale = if (matrixYaw != null) {
            HEAD_OFFSET_MATRIX_SCORE_SCALE
        } else {
            HEAD_OFFSET_RATIO_SCORE_SCALE
        }
        val headOffsetScore = updateHeadOffsetScore(
            yawMetric = yawMetric,
            scoreScale = scoreScale,
            matrixYaw = matrixYaw,
            matrixPitch = matrixPitch,
            leftEyeOpen = leftEyeOpen,
            rightEyeOpen = rightEyeOpen
        )
        if (headOffsetBaseline == null) {
            return Triple(0.0f, 0.0f, headOffsetScore)
        }

        val yawBaseline = headOffsetBaseline ?: yawMetric
        val rawYawValue = if (headOffsetScoreScale == HEAD_OFFSET_MATRIX_SCORE_SCALE) {
            yawMetric - yawBaseline
        } else {
            (yawMetric - yawBaseline) * HEAD_YAW_RATIO_DISPLAY_SCALE
        }
        val rawYaw = clamp(rawYawValue, -MAX_HEAD_YAW, MAX_HEAD_YAW)

        val rawPitch = matrixPitch ?: run {
            val normalizedNoseY = (nose.y() - forehead.y()) / (chin.y() - forehead.y())
            clamp(
                value = (normalizedNoseY - NEUTRAL_NOSE_VERTICAL_RATIO) * HEAD_PITCH_SCALE,
                minValue = -MAX_HEAD_PITCH,
                maxValue = MAX_HEAD_PITCH
            )
        }

        if (headPitchBaseline == null) {
            headPitchBaseline = rawPitch
        }

        val calibratedPitch = rawPitch - (headPitchBaseline ?: 0.0f)
        return smoothHeadPose(rawYaw, calibratedPitch, headOffsetScore)
    }

    private fun updateHeadOffsetScore(
        yawMetric: Float,
        scoreScale: Float,
        matrixYaw: Float?,
        matrixPitch: Float?,
        leftEyeOpen: Float,
        rightEyeOpen: Float
    ): Float {
        if (headOffsetBaseline == null) {
            if (canUseForHeadBaseline(matrixYaw, matrixPitch, leftEyeOpen, rightEyeOpen) &&
                isYawStableForBaseline(yawMetric)
            ) {
                headOffsetBaselineSamples.add(yawMetric)
            }
            headOffsetScore = 0.0f
            if (headOffsetBaselineSamples.size >= HEAD_OFFSET_BASELINE_SAMPLES) {
                headOffsetBaseline = median(headOffsetBaselineSamples)
                headOffsetScoreScale = scoreScale
                smoothedHeadOffsetMetric = headOffsetBaseline ?: yawMetric
                hasSmoothedHeadOffsetMetric = true
            }
            return headOffsetScore
        }

        if (!hasSmoothedHeadOffsetMetric) {
            smoothedHeadOffsetMetric = yawMetric
            hasSmoothedHeadOffsetMetric = true
        } else {
            smoothedHeadOffsetMetric = smooth(
                previous = smoothedHeadOffsetMetric,
                current = yawMetric,
                smoothing = HEAD_OFFSET_METRIC_SMOOTHING
            )
        }

        val baseline = headOffsetBaseline ?: yawMetric
        val rawScore = clamp(
            value = abs(smoothedHeadOffsetMetric - baseline) * headOffsetScoreScale,
            minValue = 0.0f,
            maxValue = 100.0f
        )
        headOffsetScore = rawScore
        return headOffsetScore
    }

    private fun canUseForHeadBaseline(
        matrixYaw: Float?,
        matrixPitch: Float?,
        leftEyeOpen: Float,
        rightEyeOpen: Float
    ): Boolean {
        if (matrixYaw == null || matrixPitch == null) return false
        if (abs(matrixPitch) > HEAD_BASELINE_MAX_ABS_PITCH) return false
        val averageEyeOpen = (leftEyeOpen + rightEyeOpen) / 2.0f
        val maxEyeOpen = max(leftEyeOpen, rightEyeOpen)
        if (averageEyeOpen < HEAD_BASELINE_MIN_AVG_EYE_OPEN) return false
        if (maxEyeOpen < HEAD_BASELINE_MIN_SINGLE_EYE_OPEN) return false
        return true
    }

    private fun isYawStableForBaseline(currentYaw: Float): Boolean {
        val last = lastBaselineCandidateYaw
        lastBaselineCandidateYaw = currentYaw
        return last == null || abs(currentYaw - last) < HEAD_BASELINE_MAX_YAW_DELTA
    }

    private fun extractYawFromMatrix(matrix: FloatArray): Float? {
        if (matrix.size < 11) return null
        return Math.toDegrees(atan2(matrix[8].toDouble(), matrix[10].toDouble())).toFloat()
    }

    private fun extractPitchFromMatrix(matrix: FloatArray): Float? {
        if (matrix.size < 11) return null
        val y = -matrix[9].toDouble()
        val x = sqrt(matrix[8] * matrix[8] + matrix[10] * matrix[10]).toDouble()
        return Math.toDegrees(atan2(y, x)).toFloat()
    }

    private fun logHeadMatrixDebug(matrix: FloatArray) {
        if (!DEBUG_HEAD_MATRIX_LOG || matrix.size < 16) return
        headMatrixDebugCounter++
        if (headMatrixDebugCounter % HEAD_MATRIX_DEBUG_INTERVAL != 0L) return

        val yawA = Math.toDegrees(atan2(matrix[8].toDouble(), matrix[10].toDouble()))
        val yawB = Math.toDegrees(atan2(-matrix[2].toDouble(), matrix[0].toDouble()))
        val pitchA = Math.toDegrees(
            atan2(
                -matrix[9].toDouble(),
                sqrt(matrix[8] * matrix[8] + matrix[10] * matrix[10]).toDouble()
            )
        )
        val pitchB = Math.toDegrees(atan2(matrix[6].toDouble(), matrix[5].toDouble()))

        Log.d(
            "HeadMatrix",
            """
            m00=${matrix[0]}, m01=${matrix[1]}, m02=${matrix[2]}, m03=${matrix[3]}
            m10=${matrix[4]}, m11=${matrix[5]}, m12=${matrix[6]}, m13=${matrix[7]}
            m20=${matrix[8]}, m21=${matrix[9]}, m22=${matrix[10]}, m23=${matrix[11]}
            m30=${matrix[12]}, m31=${matrix[13]}, m32=${matrix[14]}, m33=${matrix[15]}
            yawA=$yawA, yawB=$yawB, pitchA=$pitchA, pitchB=$pitchB
            """.trimIndent()
        )
    }

    private fun smoothHeadPose(rawYaw: Float, rawPitch: Float, headOffsetScore: Float): Triple<Float, Float, Float> {
        if (!hasSmoothedHeadPose) {
            smoothedHeadYaw = rawYaw
            smoothedHeadPitch = rawPitch
            hasSmoothedHeadPose = true
        } else {
            smoothedHeadYaw = smooth(smoothedHeadYaw, rawYaw, HEAD_POSE_SMOOTHING)
            smoothedHeadPitch = smooth(smoothedHeadPitch, rawPitch, HEAD_POSE_SMOOTHING)
        }

        return Triple(smoothedHeadYaw, smoothedHeadPitch, headOffsetScore)
    }

    private fun smooth(previous: Float, current: Float, smoothing: Float): Float {
        return previous * smoothing + current * (1.0f - smoothing)
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

    private fun median(values: List<Float>): Float {
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[middle - 1] + sorted[middle]) / 2.0f
        } else {
            sorted[middle]
        }
    }

    fun close() {
        faceLandmarker.close()
        poseLandmarker.close()
    }

    fun resetCalibration() {
        lastFaceResult = mapOf("hasFace" to false)
        lastPoseResult = mapOf("hasPose" to false)
        poseSequence = 0L
        smoothedHeadYaw = 0.0f
        smoothedHeadPitch = 0.0f
        headOffsetScore = 0.0f
        hasSmoothedHeadPose = false
        hasSmoothedHeadOffsetMetric = false
        headPitchBaseline = null
        smoothedHeadOffsetMetric = 0.0f
        headOffsetBaselineSamples.clear()
        headOffsetBaseline = null
        headOffsetScoreScale = HEAD_OFFSET_RATIO_SCORE_SCALE
        lastBaselineCandidateYaw = null
        headMatrixDebugCounter = 0L
    }

    companion object {
        private const val LEFT_SHOULDER = 11
        private const val RIGHT_SHOULDER = 12
        private const val POSE_NOSE = 0
        private const val POSE_LEFT_EYE = 2
        private const val POSE_RIGHT_EYE = 5
        private const val POSE_LEFT_EAR = 7
        private const val POSE_RIGHT_EAR = 8
        private const val NOSE_TIP = 1
        private const val FOREHEAD_TOP = 10
        private const val CHIN = 152
        private const val RIGHT_EYE_OUTER_CORNER = 33
        private const val LEFT_EYE_OUTER_CORNER = 263
        private val LEFT_EYE_POINTS = intArrayOf(362, 385, 387, 263, 373, 380)
        private val RIGHT_EYE_POINTS = intArrayOf(33, 160, 158, 133, 153, 144)
        private const val CLOSED_EYE_EAR = 0.13f
        private const val OPEN_EYE_EAR = 0.27f
        private const val HEAD_POSE_SMOOTHING = 0.45f
        private const val HEAD_OFFSET_METRIC_SMOOTHING = 0.55f
        private const val HEAD_PITCH_SCALE = 120.0f
        private const val HEAD_OFFSET_BASELINE_SAMPLES = 5
        private const val HEAD_BASELINE_MAX_ABS_PITCH = 30.0f
        private const val HEAD_BASELINE_MIN_AVG_EYE_OPEN = 0.25f
        private const val HEAD_BASELINE_MIN_SINGLE_EYE_OPEN = 0.35f
        private const val HEAD_BASELINE_MAX_YAW_DELTA = 12.0f
        private const val HEAD_OFFSET_MATRIX_SCORE_SCALE = 2.4f
        private const val HEAD_OFFSET_RATIO_SCORE_SCALE = 180.0f
        private const val HEAD_YAW_RATIO_DISPLAY_SCALE = 120.0f
        private const val MAX_HEAD_YAW = 45.0f
        private const val MAX_HEAD_PITCH = 45.0f
        private const val POSE_BOOST_HEAD_OFFSET = 45.0f
        private const val POSE_BOOST_HEAD_PITCH = 24.0f
        private const val NEUTRAL_NOSE_VERTICAL_RATIO = 0.52f
        private const val DEBUG_HEAD_MATRIX_LOG = false
        private const val HEAD_MATRIX_DEBUG_INTERVAL = 15L
    }
}
