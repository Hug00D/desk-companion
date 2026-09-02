package com.example.desk_companion

import java.io.BufferedWriter
import java.io.Closeable
import java.io.File
import java.nio.charset.StandardCharsets

class VisionFrameCsvWriter(outputFile: File) : Closeable {
    private val writer = outputFile.outputStream()
        .bufferedWriter(StandardCharsets.UTF_8)

    init {
        writer.write(HEADER)
        writer.newLine()
    }

    fun writeFrame(
        frameIndex: Int,
        timestampMs: Long,
        features: Map<String, Any>
    ) {
        val columns = listOf(
            frameIndex.toString(),
            timestampMs.toString(),
            booleanValue(features["hasFace"]),
            booleanValue(features["hasPose"]),
            numberValue(features["leftEar"]),
            numberValue(features["rightEar"]),
            numberValue(features["headYaw"]),
            numberValue(features["headPitch"]),
            numberValue(features["headOffsetScore"]),
            numberValue(features["leftEye"]),
            numberValue(features["rightEye"]),
            booleanValue(features["headOffsetCalibrating"]),
            numberValue(features["imageWidth"]),
            numberValue(features["imageHeight"]),
            numberValue(features["poseNoseX"]),
            numberValue(features["poseNoseY"]),
            numberValue(features["poseNoseVisibility"]),
            numberValue(features["poseLeftEyeX"]),
            numberValue(features["poseLeftEyeY"]),
            numberValue(features["poseLeftEyeVisibility"]),
            numberValue(features["poseRightEyeX"]),
            numberValue(features["poseRightEyeY"]),
            numberValue(features["poseRightEyeVisibility"]),
            numberValue(features["poseLeftEarX"]),
            numberValue(features["poseLeftEarY"]),
            numberValue(features["poseLeftEarVisibility"]),
            numberValue(features["poseRightEarX"]),
            numberValue(features["poseRightEarY"]),
            numberValue(features["poseRightEarVisibility"]),
            numberValue(features["lsX"]),
            numberValue(features["lsY"]),
            numberValue(features["lsVisibility"]),
            numberValue(features["rsX"]),
            numberValue(features["rsY"]),
            numberValue(features["rsVisibility"]),
            numberValue(features["poseLeftHipX"]),
            numberValue(features["poseLeftHipY"]),
            numberValue(features["poseLeftHipVisibility"]),
            numberValue(features["poseRightHipX"]),
            numberValue(features["poseRightHipY"]),
            numberValue(features["poseRightHipVisibility"]),
            "",
            "",
            "",
            "",
            ""
        )
        writer.write(columns.joinToString(","))
        writer.newLine()
    }

    override fun close() {
        writer.close()
    }

    fun flush() {
        writer.flush()
    }

    private fun booleanValue(value: Any?): String = when (value) {
        true -> "true"
        false -> "false"
        else -> ""
    }

    private fun numberValue(value: Any?): String = (value as? Number)?.toString() ?: ""

    companion object {
        const val HEADER =
            "frame_idx,timestamp_ms,face_detected,pose_detected," +
                "ear_l,ear_r,yaw,pitch,head_offset," +
                "eye_open_l,eye_open_r,head_offset_calibrating," +
                "image_width,image_height," +
                "pose_nose_x,pose_nose_y,pose_nose_visibility," +
                "pose_left_eye_x,pose_left_eye_y,pose_left_eye_visibility," +
                "pose_right_eye_x,pose_right_eye_y,pose_right_eye_visibility," +
                "pose_left_ear_x,pose_left_ear_y,pose_left_ear_visibility," +
                "pose_right_ear_x,pose_right_ear_y,pose_right_ear_visibility," +
                "pose_left_shoulder_x,pose_left_shoulder_y,pose_left_shoulder_visibility," +
                "pose_right_shoulder_x,pose_right_shoulder_y,pose_right_shoulder_visibility," +
                "pose_left_hip_x,pose_left_hip_y,pose_left_hip_visibility," +
                "pose_right_hip_x,pose_right_hip_y,pose_right_hip_visibility," +
                "raw_eye_closed,raw_head_turned,raw_posture_down," +
                "raw_user_missing,raw_state"
    }
}
