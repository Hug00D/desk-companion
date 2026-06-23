package com.example.desk_companion

import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channel = "com.example.desk_companion/cv_channel"
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var visionExecutor: ExecutorService
    private var frameCounter = 0L
    private val visionManagerDelegate = lazy {
        MediaPipeVisionManager(this)
    }
    private val visionManager: MediaPipeVisionManager by visionManagerDelegate

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

                "resetVision" -> {
                    frameCounter = 0L
                    if (visionManagerDelegate.isInitialized()) {
                        visionManager.resetCalibration()
                    }
                    result.success("OK")
                }

                "copyNativeAssetToCache" -> {
                    val assetName = call.argument<String>("assetName")
                    val outputFileName = call.argument<String>("outputFileName")
                    if (assetName.isNullOrBlank() || outputFileName.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "assetName and outputFileName are required", null)
                    } else {
                        copyNativeAssetToCache(assetName, outputFileName, result)
                    }
                }

                "extractVideoFrame" -> {
                    val videoPath = call.argument<String>("videoPath")
                    val timeMs = call.argument<Int>("timeMs")
                    val quality = call.argument<Int>("quality") ?: 85
                    if (videoPath.isNullOrBlank() || timeMs == null) {
                        result.error("INVALID_ARGUMENT", "videoPath and timeMs are required", null)
                    } else {
                        extractVideoFrame(videoPath, timeMs, quality, result)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun copyNativeAssetToCache(
        assetName: String,
        outputFileName: String,
        result: MethodChannel.Result
    ) {
        try {
            val outputFile = File(cacheDir, outputFileName)
            assets.open(assetName).use { input ->
                outputFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            result.success(outputFile.absolutePath)
        } catch (e: Exception) {
            result.error("ASSET_COPY_ERROR", e.message, null)
        }
    }

    private fun extractVideoFrame(
        videoPath: String,
        timeMs: Int,
        quality: Int,
        result: MethodChannel.Result
    ) {
        visionExecutor.execute {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(videoPath)
                val durationMs = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                val bitmap = extractBestAvailableFrame(retriever, timeMs, durationMs)
                    ?: throw IllegalStateException("Unable to extract video frame at ${timeMs}ms")

                val output = ByteArrayOutputStream()
                try {
                    bitmap.compress(
                        android.graphics.Bitmap.CompressFormat.JPEG,
                        quality.coerceIn(1, 100),
                        output
                    )
                } finally {
                    bitmap.recycle()
                }

                mainHandler.post {
                    result.success(output.toByteArray())
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("VIDEO_FRAME_ERROR", e.message, null)
                }
            } finally {
                retriever.release()
            }
        }
    }

    private fun extractBestAvailableFrame(
        retriever: MediaMetadataRetriever,
        requestedTimeMs: Int,
        durationMs: Long?
    ): android.graphics.Bitmap? {
        val requested = requestedTimeMs.coerceAtLeast(0).toLong()
        val candidateTimesMs = buildList {
            add(requested)
            add(0L)
            if (durationMs != null && durationMs > 0L) {
                add((durationMs / 2L).coerceAtLeast(0L))
                add((durationMs - 1_000L).coerceAtLeast(0L))
            }
        }.distinct()

        val options = intArrayOf(
            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
            MediaMetadataRetriever.OPTION_NEXT_SYNC,
            MediaMetadataRetriever.OPTION_CLOSEST
        )

        for (timeMs in candidateTimesMs) {
            val timeUs = timeMs * 1000L
            for (option in options) {
                val frame = retriever.getFrameAtTime(timeUs, option)
                if (frame != null) return frame
            }
        }

        return retriever.frameAtTime
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        visionExecutor.execute {
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            try {
                if (bitmap == null) {
                    throw IllegalArgumentException("Unable to decode image data")
                }
                frameCounter++

                val resultMap = visionManager.analyze(
                    bitmap = bitmap,
                    runFace = shouldRun(frameCounter, FACE_DETECTION_INTERVAL),
                    runPose = shouldRun(frameCounter, POSE_DETECTION_INTERVAL)
                )

                mainHandler.post {
                    result.success(resultMap)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("PROCESS_ERROR", e.message, null)
                }
            } finally {
                bitmap?.recycle()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (visionManagerDelegate.isInitialized()) {
            visionManager.close()
        }
        if (::visionExecutor.isInitialized) {
            visionExecutor.shutdown()
        }
    }

    private fun shouldRun(frameNumber: Long, interval: Int): Boolean {
        return (frameNumber - 1L) % interval == 0L
    }

    companion object {
        private const val FACE_DETECTION_INTERVAL = 1
        private const val POSE_DETECTION_INTERVAL = 3
    }
}
