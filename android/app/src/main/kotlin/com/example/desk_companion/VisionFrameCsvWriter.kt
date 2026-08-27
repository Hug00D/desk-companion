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
                "raw_eye_closed,raw_head_turned,raw_posture_down," +
                "raw_user_missing,raw_state"
    }
}
