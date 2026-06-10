package com.example.desk_companion

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channel = "com.example.desk_companion/cv_channel"
    private val voiceChannel = "com.example.desk_companion/voice_channel"
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

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "formatVoiceResult" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val transcript = arguments?.get("transcript") as? String
                    if (transcript.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "transcript is required", null)
                    } else {
                        result.success(formatVoiceResult(arguments, transcript))
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun formatVoiceResult(arguments: Map<*, *>?, transcript: String): String {
        val confidence = (arguments?.get("confidence") as? Number)?.toDouble()
        val rmsDb = (arguments?.get("rmsDb") as? Number)?.toDouble()

        return VoiceResultJsonFormatter.formatFinalResult(
            transcript = transcript,
            formattedTranscript = arguments?.get("formattedTranscript") as? String ?: transcript,
            source = arguments?.get("source") as? String ?: "android",
            caseId = arguments?.get("caseId") as? String ?: "voice_result",
            sessionId = arguments?.get("sessionId") as? String ?: "voice-session-${System.currentTimeMillis()}",
            candidates = listOf(VoiceCandidate(text = transcript, confidence = confidence)),
            audio = VoiceAudioInfo(
                rmsDb = rmsDb,
                isSpeechDetected = arguments?.get("isSpeechDetected") as? Boolean ?: transcript.isNotBlank()
            ),
            language = VoiceLanguageInfo(
                tag = arguments?.get("languageTag") as? String ?: "zh-TW",
                confidenceLevel = arguments?.get("languageConfidenceLevel") as? String ?: "confident"
            )
        )
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
