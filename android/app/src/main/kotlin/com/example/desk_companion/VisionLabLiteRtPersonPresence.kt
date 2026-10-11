package com.example.desk_companion

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import java.io.BufferedWriter
import java.io.Closeable
import java.io.File
import java.io.FileWriter

data class VisionLabPersonPresenceSample(
    val meanConfidence: Float,
    val areaRatio: Float,
    val centroidX: Float?,
    val centroidY: Float?,
    val inferenceMs: Double
)

/**
 * Vision Lab-only direct LiteRT runner for the MediaPipe selfie segmenter.
 *
 * This deliberately does not use MediaPipe ImageSegmenter: that Task Graph
 * crashes in the x86_64/ARM-translation emulator on its first inference. The
 * formal app never constructs this class; the Vision Lab compile-time flag is
 * the only caller.
 */
class VisionLabLiteRtPersonPresence(context: Context) : Closeable {
    private val model = CompiledModel.create(
        context.assets,
        MODEL_ASSET_PATH,
        CompiledModel.Options(Accelerator.CPU),
        null
    )
    private val inputBuffers = model.createInputBuffers()
    private val outputBuffers = model.createOutputBuffers()

    init {
        require(inputBuffers.size == 1) {
            "Selfie segmenter must have one input, found ${inputBuffers.size}"
        }
        require(outputBuffers.size == 1) {
            "Selfie segmenter must have one output, found ${outputBuffers.size}"
        }
    }

    fun analyze(bitmap: Bitmap): VisionLabPersonPresenceSample {
        val scaled = Bitmap.createScaledBitmap(bitmap, INPUT_WIDTH, INPUT_HEIGHT, true)
        try {
            val pixels = IntArray(INPUT_WIDTH * INPUT_HEIGHT)
            scaled.getPixels(
                pixels,
                0,
                INPUT_WIDTH,
                0,
                0,
                INPUT_WIDTH,
                INPUT_HEIGHT
            )
            val input = FloatArray(INPUT_WIDTH * INPUT_HEIGHT * INPUT_CHANNELS)
            var inputIndex = 0
            for (pixel in pixels) {
                input[inputIndex++] = ((pixel shr 16) and 0xff) / 255.0f
                input[inputIndex++] = ((pixel shr 8) and 0xff) / 255.0f
                input[inputIndex++] = (pixel and 0xff) / 255.0f
            }

            inputBuffers[0].writeFloat(input)
            val inferenceStartedNs = SystemClock.elapsedRealtimeNanos()
            model.run(inputBuffers, outputBuffers)
            val inferenceMs =
                (SystemClock.elapsedRealtimeNanos() - inferenceStartedNs) / 1_000_000.0
            val output = outputBuffers[0].readFloat()
            require(output.size == OUTPUT_WIDTH * OUTPUT_HEIGHT) {
                "Unexpected selfie segmenter output length: ${output.size}"
            }

            var confidenceSum = 0.0
            var personPixels = 0L
            var personXSum = 0L
            var personYSum = 0L
            for (y in 0 until OUTPUT_HEIGHT) {
                for (x in 0 until OUTPUT_WIDTH) {
                    val confidence = output[y * OUTPUT_WIDTH + x]
                    confidenceSum += confidence
                    if (confidence >= PERSON_PIXEL_THRESHOLD) {
                        personPixels++
                        personXSum += x.toLong()
                        personYSum += y.toLong()
                    }
                }
            }
            val pixelCount = OUTPUT_WIDTH.toLong() * OUTPUT_HEIGHT.toLong()
            return VisionLabPersonPresenceSample(
                meanConfidence = (confidenceSum / pixelCount).toFloat(),
                areaRatio = personPixels.toFloat() / pixelCount,
                centroidX = if (personPixels == 0L) {
                    null
                } else {
                    personXSum.toFloat() / personPixels / (OUTPUT_WIDTH - 1)
                },
                centroidY = if (personPixels == 0L) {
                    null
                } else {
                    personYSum.toFloat() / personPixels / (OUTPUT_HEIGHT - 1)
                },
                inferenceMs = inferenceMs
            )
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }

    override fun close() {
        inputBuffers.forEach { it.close() }
        outputBuffers.forEach { it.close() }
        model.close()
    }

    companion object {
        private const val MODEL_ASSET_PATH = "selfie_segmenter.tflite"
        private const val INPUT_WIDTH = 256
        private const val INPUT_HEIGHT = 256
        private const val INPUT_CHANNELS = 3
        private const val OUTPUT_WIDTH = 256
        private const val OUTPUT_HEIGHT = 256
        private const val PERSON_PIXEL_THRESHOLD = 0.5f
        const val SAMPLE_INTERVAL_MS = 200L
    }
}

class VisionLabPersonPresenceCsvWriter(outputFile: File) : Closeable {
    private val writer: BufferedWriter = BufferedWriter(FileWriter(outputFile, false))
    var sampleCount: Int = 0
        private set

    init {
        writer.write(
            "frame_idx,timestamp_ms,person_mask_mean_confidence," +
                "person_mask_area_ratio,person_mask_centroid_x," +
                "person_mask_centroid_y,inference_ms"
        )
        writer.newLine()
    }

    fun write(frameIndex: Int, timestampMs: Long, sample: VisionLabPersonPresenceSample) {
        writer.write(
            listOf(
                frameIndex.toString(),
                timestampMs.toString(),
                sample.meanConfidence.toString(),
                sample.areaRatio.toString(),
                sample.centroidX?.toString() ?: "",
                sample.centroidY?.toString() ?: "",
                sample.inferenceMs.toString()
            ).joinToString(",")
        )
        writer.newLine()
        sampleCount++
    }

    fun flush() = writer.flush()

    override fun close() = writer.close()
}
