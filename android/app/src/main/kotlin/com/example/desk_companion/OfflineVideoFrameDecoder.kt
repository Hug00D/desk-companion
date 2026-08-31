package com.example.desk_companion

import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

data class OfflineVideoDecodeSummary(
    val frameCount: Int,
    val droppedTimestampsMs: List<Long>,
    val sourceFrameCount: Int?,
    val metadataFrameCount: Int?,
    val firstTimestampMs: Long?,
    val lastTimestampMs: Long?
)

/**
 * Decodes every video frame in presentation order and exposes the decoder's
 * presentation timestamp. Playback and Flutter UI state are deliberately not
 * involved in this path.
 */
class OfflineVideoFrameDecoder(
    private val maxAnalysisDimension: Int = 640
) {
    fun decode(
        videoPath: String,
        onFrame: (frameIndex: Int, timestampMs: Long, bitmap: Bitmap) -> Unit
    ): OfflineVideoDecodeSummary {
        require(File(videoPath).isFile) { "Video does not exist: $videoPath" }

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            val metadataFrameCount = readMetadataFrameCount(videoPath)
            extractor.setDataSource(videoPath)
            val trackIndex = findVideoTrack(extractor)
            require(trackIndex >= 0) { "No video track found: $videoPath" }
            extractor.selectTrack(trackIndex)

            val format = extractor.getTrackFormat(trackIndex)
            val mime = requireNotNull(format.getString(MediaFormat.KEY_MIME)) {
                "Video track is missing a MIME type"
            }
            val rotationDegrees = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                format.getInteger(MediaFormat.KEY_ROTATION)
            } else {
                0
            }
            format.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
            )

            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            val bufferInfo = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var frameIndex = 0
            var firstTimestampMs: Long? = null
            var lastTimestampMs: Long? = null
            val inputTimestampsMs = mutableListOf<Long>()
            val outputTimestampsMs = mutableListOf<Long>()

            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = decoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val inputBuffer = requireNotNull(decoder.getInputBuffer(inputIndex))
                        inputBuffer.clear()
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputEnded = true
                        } else {
                            inputTimestampsMs.add(extractor.sampleTime / 1_000L)
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                sampleSize,
                                extractor.sampleTime,
                                extractor.sampleFlags
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = decoder.dequeueOutputBuffer(bufferInfo, CODEC_TIMEOUT_US)
                when {
                    outputIndex >= 0 -> {
                        try {
                            val isCodecConfig =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            val isEndOfStream =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            val outputImage = if (!isCodecConfig) {
                                decoder.getOutputImage(outputIndex)
                            } else {
                                null
                            }
                            val candidateTimestampMs =
                                bufferInfo.presentationTimeUs / 1_000L
                            val isFreshTimestamp = lastTimestampMs == null ||
                                candidateTimestampMs > lastTimestampMs
                            val containsFrame = outputImage != null &&
                                (!isEndOfStream || isFreshTimestamp)
                            if (containsFrame) {
                                val timestampMs = candidateTimestampMs
                                val previousTimestampMs = lastTimestampMs
                                require(previousTimestampMs == null || timestampMs > previousTimestampMs) {
                                    "Video PTS must be strictly increasing in milliseconds: " +
                                        "previous=$previousTimestampMs current=$timestampMs"
                                }

                                requireNotNull(outputImage).use { image ->
                                    val sourceBitmap = yuv420ToBitmap(image)
                                    val analysisBitmap = prepareAnalysisBitmap(
                                        source = sourceBitmap,
                                        rotationDegrees = rotationDegrees
                                    )
                                    try {
                                        onFrame(frameIndex, timestampMs, analysisBitmap)
                                    } finally {
                                        analysisBitmap.recycle()
                                    }
                                }

                                if (firstTimestampMs == null) firstTimestampMs = timestampMs
                                lastTimestampMs = timestampMs
                                outputTimestampsMs.add(timestampMs)
                                frameIndex++
                            } else {
                                outputImage?.close()
                                if (!isCodecConfig && !isEndOfStream) {
                                    error(
                                        "Decoder produced no image at PTS " +
                                            "${bufferInfo.presentationTimeUs}us"
                                    )
                                }
                            }
                        } finally {
                            decoder.releaseOutputBuffer(outputIndex, false)
                        }

                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputEnded = true
                        }
                    }

                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                }
            }

            val inputTimestampSet = inputTimestampsMs.toSet()
            val outputTimestampSet = outputTimestampsMs.toSet()
            val missingTimestamps = inputTimestampSet - outputTimestampSet
            val unexpectedTimestamps = outputTimestampSet - inputTimestampSet
            // A PTS the extractor never carried means the output is corrupt, so that
            // still fails. A sample the decoder declined to emit is reported instead:
            // the run stays reproducible, and the caller sees how many frames were lost.
            require(unexpectedTimestamps.isEmpty()) {
                "Decoded PTS not present in extractor samples: " +
                    "input=${inputTimestampsMs.size} output=${outputTimestampsMs.size} " +
                    "unexpected=${unexpectedTimestamps.take(5)}"
            }
            val droppedTimestampsMs = missingTimestamps.sorted()
            if (droppedTimestampsMs.isNotEmpty()) {
                Log.w(
                    LOG_TAG,
                    "decoder dropped ${droppedTimestampsMs.size} sample(s): " +
                        "droppedMs=${droppedTimestampsMs.take(10)} " +
                        "input=${inputTimestampsMs.size} output=${outputTimestampsMs.size} " +
                        "lastInputMs=${inputTimestampsMs.maxOrNull()} " +
                        "lastOutputMs=${outputTimestampsMs.lastOrNull()}"
                )
            }
            return OfflineVideoDecodeSummary(
                frameCount = frameIndex,
                droppedTimestampsMs = droppedTimestampsMs,
                sourceFrameCount = inputTimestampsMs.size,
                metadataFrameCount = metadataFrameCount,
                firstTimestampMs = firstTimestampMs,
                lastTimestampMs = lastTimestampMs
            )
        } finally {
            try {
                decoder?.stop()
            } catch (_: IllegalStateException) {
                // The decoder may fail before start(); release still has to run.
            }
            decoder?.release()
            extractor.release()
        }
    }

    private fun findVideoTrack(extractor: MediaExtractor): Int {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("video/") == true) return index
        }
        return -1
    }

    private fun readMetadataFrameCount(videoPath: String): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)
                ?.toIntOrNull()
        } finally {
            retriever.release()
        }
    }

    private fun yuv420ToBitmap(image: Image): Bitmap {
        require(image.format == ImageFormat.YUV_420_888) {
            "Expected YUV_420_888 output, received format=${image.format}"
        }
        val crop = image.cropRect
        val sourceWidth = crop.width()
        val sourceHeight = crop.height()
        val sourceMaxDimension = max(sourceWidth, sourceHeight)
        val scale = if (sourceMaxDimension > maxAnalysisDimension) {
            maxAnalysisDimension.toFloat() / sourceMaxDimension
        } else {
            1.0f
        }
        val width = (sourceWidth * scale).roundToInt().coerceAtLeast(1)
        val height = (sourceHeight * scale).roundToInt().coerceAtLeast(1)
        val planes = image.planes
        require(planes.size >= 3) { "YUV frame has fewer than three planes" }

        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yBase = yBuffer.position()
        val uBase = uBuffer.position()
        val vBase = vBuffer.position()
        val pixels = IntArray(width * height)

        for (row in 0 until height) {
            val sourceY = crop.top + ((row + 0.5f) * sourceHeight / height)
                .toInt()
                .coerceIn(0, sourceHeight - 1)
            val chromaY = sourceY / 2
            for (column in 0 until width) {
                val sourceX = crop.left + ((column + 0.5f) * sourceWidth / width)
                    .toInt()
                    .coerceIn(0, sourceWidth - 1)
                val chromaX = sourceX / 2
                val yIndex = yBase +
                    sourceY * yPlane.rowStride +
                    sourceX * yPlane.pixelStride
                val uIndex = uBase +
                    chromaY * uPlane.rowStride +
                    chromaX * uPlane.pixelStride
                val vIndex = vBase +
                    chromaY * vPlane.rowStride +
                    chromaX * vPlane.pixelStride

                val y = yBuffer.get(yIndex).toInt() and 0xff
                val u = uBuffer.get(uIndex).toInt() and 0xff
                val v = vBuffer.get(vIndex).toInt() and 0xff
                pixels[row * width + column] = yuvToArgb(y, u, v)
            }
        }

        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun yuvToArgb(y: Int, u: Int, v: Int): Int {
        val c = max(0, y - 16)
        val d = u - 128
        val e = v - 128
        val red = clampColor((298 * c + 409 * e + 128) shr 8)
        val green = clampColor((298 * c - 100 * d - 208 * e + 128) shr 8)
        val blue = clampColor((298 * c + 516 * d + 128) shr 8)
        return (0xff shl 24) or (red shl 16) or (green shl 8) or blue
    }

    private fun clampColor(value: Int): Int = value.coerceIn(0, 255)

    private fun prepareAnalysisBitmap(source: Bitmap, rotationDegrees: Int): Bitmap {
        val rotated = if (rotationDegrees == 0) {
            source
        } else {
            Bitmap.createBitmap(
                source,
                0,
                0,
                source.width,
                source.height,
                Matrix().apply { postRotate(rotationDegrees.toFloat()) },
                true
            ).also { source.recycle() }
        }

        val maxDimension = max(rotated.width, rotated.height)
        if (maxDimension <= maxAnalysisDimension) return rotated

        val scale = maxAnalysisDimension.toFloat() / maxDimension
        return Bitmap.createScaledBitmap(
            rotated,
            (rotated.width * scale).toInt().coerceAtLeast(1),
            (rotated.height * scale).toInt().coerceAtLeast(1),
            true
        ).also { scaled ->
            if (scaled !== rotated) rotated.recycle()
        }
    }

    companion object {
        private const val CODEC_TIMEOUT_US = 10_000L
        private const val LOG_TAG = "VisionLab"
    }
}
