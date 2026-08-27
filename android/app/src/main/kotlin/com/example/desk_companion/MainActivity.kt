package com.example.desk_companion

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.Size
import android.view.View
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var visionExecutor: ExecutorService
    private var visionEventSink: EventChannel.EventSink? = null
    private var pendingCameraStartResult: MethodChannel.Result? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var previewView: PreviewView? = null
    private var isVisionCameraRunning = false
    private var lastFaceAnalysisAtMs = Long.MIN_VALUE
    private var lastPoseAnalysisAtMs = Long.MIN_VALUE
    private var cameraWarmupUntilMs = 0L
    private var lastTaskTimestampMs = 0L
    private var lastVisionErrorAtMs = Long.MIN_VALUE
    private val visionManagerDelegate = lazy {
        MediaPipeVisionManager(this)
    }
    private val visionManager: MediaPipeVisionManager by visionManagerDelegate

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        visionExecutor = Executors.newSingleThreadExecutor()

        flutterEngine.platformViewsController.registry.registerViewFactory(
            CAMERA_PREVIEW_VIEW_TYPE,
            VisionCameraPreviewFactory(this)
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VISION_EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                visionEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                visionEventSink = null
                stopVisionCamera()
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
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

                "startCamera" -> requestVisionCameraStart(result)

                "stopCamera" -> {
                    stopVisionCamera()
                    result.success("OK")
                }

                "resetVision" -> resetVision(result)

                "extractVideoFeaturesToCsv" -> {
                    val videoPath = call.argument<String>("videoPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (videoPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "videoPath and outputPath are required",
                            null
                        )
                    } else if (isVisionCameraRunning) {
                        result.error(
                            "CAMERA_RUNNING",
                            "Stop the live camera before starting offline extraction",
                            null
                        )
                    } else {
                        extractVideoFeaturesToCsv(videoPath, outputPath, result)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun processImage(data: ByteArray, result: MethodChannel.Result) {
        visionExecutor.execute {
            val bitmap = decodeAnalysisBitmap(data)
            try {
                if (bitmap == null) {
                    throw IllegalArgumentException("Unable to decode image data")
                }

                val resultMap = visionManager.analyze(
                    bitmap = bitmap,
                    runFace = true,
                    runPose = true,
                    timestampMs = nextTaskTimestampMs()
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

    private fun decodeAnalysisBitmap(data: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)

        var sampleSize = 1
        while (max(bounds.outWidth, bounds.outHeight) / sampleSize > MAX_ANALYSIS_DIMENSION) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeByteArray(data, 0, data.size, options)
    }

    private fun requestVisionCameraStart(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startVisionCamera(result)
            return
        }

        pendingCameraStartResult?.error(
            "CAMERA_REQUEST_REPLACED",
            "A newer camera request replaced the previous request",
            null
        )
        pendingCameraStartResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST_CODE) return

        val pendingResult = pendingCameraStartResult ?: return
        pendingCameraStartResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startVisionCamera(pendingResult)
        } else {
            pendingResult.error(
                "CAMERA_PERMISSION_DENIED",
                "Camera permission was denied",
                null
            )
        }
    }

    private fun startVisionCamera(result: MethodChannel.Result) {
        if (isVisionCameraRunning) {
            result.success("OK")
            return
        }

        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            try {
                cameraProvider = providerFuture.get()
                isVisionCameraRunning = true
                resetAnalysisSchedule()
                bindCameraUseCases()
                result.success("OK")
            } catch (e: Exception) {
                isVisionCameraRunning = false
                result.error("CAMERA_START_ERROR", e.message, null)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bindCameraUseCases() {
        val provider = cameraProvider ?: return
        if (!isVisionCameraRunning) return

        imageAnalysis?.clearAnalyzer()
        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(ANALYSIS_WIDTH, ANALYSIS_HEIGHT))
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
        analysis.setAnalyzer(visionExecutor, ::analyzeCameraFrame)
        imageAnalysis = analysis

        val cameraSelector = when {
            provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ->
                CameraSelector.DEFAULT_FRONT_CAMERA
            provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ->
                CameraSelector.DEFAULT_BACK_CAMERA
            else -> throw IllegalStateException("No camera is available")
        }

        val useCases = mutableListOf<androidx.camera.core.UseCase>(analysis)
        previewView?.let { view ->
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(view.surfaceProvider)
            }
            useCases.add(preview)
        }

        provider.unbindAll()
        provider.bindToLifecycle(this, cameraSelector, *useCases.toTypedArray())
    }

    private fun analyzeCameraFrame(imageProxy: ImageProxy) {
        var analysisBitmap: Bitmap? = null
        try {
            val nowMs = SystemClock.elapsedRealtime()
            val runFace = elapsedAtLeast(
                nowMs,
                lastFaceAnalysisAtMs,
                FACE_ANALYSIS_INTERVAL_MS
            )
            val shouldBoostPose = nowMs < cameraWarmupUntilMs ||
                !visionManagerDelegate.isInitialized() ||
                visionManager.shouldBoostPose()
            val poseIntervalMs = if (shouldBoostPose) {
                POSE_BOOST_INTERVAL_MS
            } else {
                POSE_STABLE_INTERVAL_MS
            }
            val runPose = elapsedAtLeast(nowMs, lastPoseAnalysisAtMs, poseIntervalMs)

            if (!runFace && !runPose) return

            analysisBitmap = prepareAnalysisBitmap(imageProxy)
            val resultMap = visionManager.analyze(
                bitmap = analysisBitmap,
                runFace = runFace,
                runPose = runPose,
                timestampMs = nextTaskTimestampMs()
            )
            if (runFace) lastFaceAnalysisAtMs = nowMs
            if (runPose) lastPoseAnalysisAtMs = nowMs

            mainHandler.post {
                visionEventSink?.success(resultMap)
            }
        } catch (e: Exception) {
            emitVisionError(e)
        } finally {
            analysisBitmap?.recycle()
            imageProxy.close()
        }
    }

    private fun prepareAnalysisBitmap(imageProxy: ImageProxy): Bitmap {
        val source = imageProxy.toBitmap()
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
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
        if (maxDimension <= MAX_ANALYSIS_DIMENSION) return rotated

        val scale = MAX_ANALYSIS_DIMENSION.toFloat() / maxDimension
        return Bitmap.createScaledBitmap(
            rotated,
            (rotated.width * scale).toInt(),
            (rotated.height * scale).toInt(),
            true
        ).also { scaled ->
            if (scaled !== rotated) rotated.recycle()
        }
    }

    private fun elapsedAtLeast(nowMs: Long, previousMs: Long, intervalMs: Long): Boolean {
        return previousMs == Long.MIN_VALUE || nowMs - previousMs >= intervalMs
    }

    private fun nextTaskTimestampMs(): Long {
        val nowMs = SystemClock.uptimeMillis()
        lastTaskTimestampMs = max(nowMs, lastTaskTimestampMs + 1L)
        return lastTaskTimestampMs
    }

    private fun resetAnalysisSchedule() {
        lastFaceAnalysisAtMs = Long.MIN_VALUE
        lastPoseAnalysisAtMs = Long.MIN_VALUE
        cameraWarmupUntilMs = SystemClock.elapsedRealtime() + CAMERA_WARMUP_DURATION_MS
    }

    private fun emitVisionError(error: Exception) {
        val nowMs = SystemClock.elapsedRealtime()
        if (!elapsedAtLeast(nowMs, lastVisionErrorAtMs, ERROR_REPORT_INTERVAL_MS)) return
        lastVisionErrorAtMs = nowMs
        mainHandler.post {
            visionEventSink?.error("CAMERA_ANALYSIS_ERROR", error.message, null)
        }
    }

    private fun resetVision(result: MethodChannel.Result) {
        visionExecutor.execute {
            if (visionManagerDelegate.isInitialized()) {
                visionManager.resetCalibration()
            }
            resetAnalysisSchedule()
            mainHandler.post { result.success("OK") }
        }
    }

    private fun extractVideoFeaturesToCsv(
        videoPath: String,
        outputPath: String,
        result: MethodChannel.Result
    ) {
        visionExecutor.execute {
            val outputFile = File(outputPath)
            var labVisionManager: MediaPipeVisionManager? = null
            try {
                require(File(videoPath).isFile) { "Video does not exist: $videoPath" }
                require(!outputFile.exists()) { "Output already exists: $outputPath" }
                require(outputFile.parentFile?.isDirectory == true) {
                    "Output directory does not exist: ${outputFile.parent}"
                }

                labVisionManager = MediaPipeVisionManager(applicationContext)
                val manager = labVisionManager
                val summary = VisionFrameCsvWriter(outputFile).use { csvWriter ->
                    OfflineVideoFrameDecoder(MAX_ANALYSIS_DIMENSION).decode(videoPath) {
                        frameIndex,
                        timestampMs,
                        bitmap ->
                        val features = manager.analyze(
                            bitmap = bitmap,
                            runFace = true,
                            runPose = true,
                            timestampMs = timestampMs
                        )
                        csvWriter.writeFrame(frameIndex, timestampMs, features)
                        if ((frameIndex + 1) % VISION_LAB_PROGRESS_INTERVAL == 0) {
                            csvWriter.flush()
                            Log.d(
                                VISION_LAB_LOG_TAG,
                                "extractedFrames=${frameIndex + 1} timestampMs=$timestampMs"
                            )
                        }
                    }
                }

                mainHandler.post {
                    result.success(
                        mapOf(
                            "outputPath" to outputFile.absolutePath,
                            "frameCount" to summary.frameCount,
                            "droppedFrameCount" to summary.droppedTimestampsMs.size,
                            "sourceFrameCount" to summary.sourceFrameCount,
                            "metadataFrameCount" to summary.metadataFrameCount,
                            "firstTimestampMs" to summary.firstTimestampMs,
                            "lastTimestampMs" to summary.lastTimestampMs
                        )
                    )
                }
            } catch (error: Exception) {
                if (outputFile.exists()) outputFile.delete()
                mainHandler.post {
                    result.error("VIDEO_EXTRACTION_ERROR", error.message, null)
                }
            } finally {
                labVisionManager?.close()
            }
        }
    }

    private fun stopVisionCamera() {
        isVisionCameraRunning = false
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        cameraProvider?.unbindAll()
    }

    internal fun attachCameraPreview(view: PreviewView) {
        previewView = view
        if (isVisionCameraRunning) {
            bindCameraUseCases()
        }
    }

    internal fun detachCameraPreview(view: PreviewView) {
        if (previewView !== view) return
        previewView = null
        if (isVisionCameraRunning) {
            bindCameraUseCases()
        }
    }

    override fun onDestroy() {
        pendingCameraStartResult?.error(
            "ACTIVITY_DESTROYED",
            "The activity was destroyed before the camera started",
            null
        )
        pendingCameraStartResult = null
        visionEventSink = null
        stopVisionCamera()
        if (visionManagerDelegate.isInitialized()) {
            visionManager.close()
        }
        if (::visionExecutor.isInitialized) {
            visionExecutor.shutdown()
        }
        super.onDestroy()
    }

    companion object {
        private const val METHOD_CHANNEL = "com.example.desk_companion/cv_channel"
        private const val VISION_EVENT_CHANNEL =
            "com.example.desk_companion/cv_stream"
        private const val CAMERA_PREVIEW_VIEW_TYPE =
            "com.example.desk_companion/camera_preview"
        private const val CAMERA_PERMISSION_REQUEST_CODE = 4201
        private const val ANALYSIS_WIDTH = 640
        private const val ANALYSIS_HEIGHT = 480
        private const val MAX_ANALYSIS_DIMENSION = 640
        private const val FACE_ANALYSIS_INTERVAL_MS = 600L
        private const val POSE_STABLE_INTERVAL_MS = 1200L
        private const val POSE_BOOST_INTERVAL_MS = 600L
        private const val CAMERA_WARMUP_DURATION_MS = 4_000L
        private const val ERROR_REPORT_INTERVAL_MS = 5_000L
        private const val VISION_LAB_PROGRESS_INTERVAL = 100
        private const val VISION_LAB_LOG_TAG = "VisionLab"
    }
}

private class VisionCameraPreviewFactory(
    private val activity: MainActivity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return VisionCameraPreview(context, activity)
    }
}

private class VisionCameraPreview(
    context: Context,
    private val activity: MainActivity
) : PlatformView {
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }

    init {
        activity.attachCameraPreview(previewView)
    }

    override fun getView(): View = previewView

    override fun dispose() {
        activity.detachCameraPreview(previewView)
    }
}
