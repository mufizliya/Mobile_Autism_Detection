package com.example.autism_detection_mobile_replica

import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.graphics.PointF
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import kotlin.math.pow
import kotlin.math.sqrt

class NativeFaceRecorder(
    private val context: Context
) {
    private val cameraExecutor: ExecutorService =
        Executors.newSingleThreadExecutor()

    private val detector: FaceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
    .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
    .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
    .setMinFaceSize(0.12f)
    .build()

        FaceDetection.getClient(options)
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var isRecording = false
    private var startedAtMs = 0L
    private var lastProcessedAtMs = 0L
    private var frameIndex = 0

    private val processEveryMs = 500L
    private val maxFrames = 600

    private val frames = mutableListOf<JSONObject>()

    fun start(
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        if (isRecording) {
            onSuccess()
            return
        }

        frames.clear()
        frameIndex = 0
        startedAtMs = SystemClock.elapsedRealtime()
        lastProcessedAtMs = 0L
        isRecording = true

        val providerFuture = ProcessCameraProvider.getInstance(context)

        providerFuture.addListener(
            {
                try {
                    cameraProvider = providerFuture.get()

                    val analyzer = ImageAnalysis.Builder()
                        .setBackpressureStrategy(
                            ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
                        )
                        .build()

                    analyzer.setAnalyzer(
                        cameraExecutor
                    ) { imageProxy ->
                        analyzeFrame(imageProxy)
                    }

                    val cameraSelector = CameraSelector.Builder()
                        .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                        .build()

                    cameraProvider?.unbindAll()
                    cameraProvider?.bindToLifecycle(
                        context as LifecycleOwner,
                        cameraSelector,
                        analyzer
                    )

                    onSuccess()
                } catch (e: Exception) {
                    isRecording = false
                    onError(e.message ?: "Unable to start native face recorder")
                }
            },
            ContextCompat.getMainExecutor(context)
        )
    }

    fun stop(
        onSuccess: (Map<String, Any?>) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            isRecording = false
            cameraProvider?.unbindAll()

            val summary = buildSummary()

            val payload = mapOf(
                "schema_version" to "mobile_native_framewise_face_signals_v1",
                "generated_at" to System.currentTimeMillis(),
                "sample_interval_ms" to processEveryMs,
                "frame_count" to frames.size,
                "summary" to summary.toMap(),
                "frames" to frames.map { it.toMap() },
            )

            onSuccess(payload)
        } catch (e: Exception) {
            onError(e.message ?: "Unable to stop native face recorder")
        }
    }

    fun shutdown() {
        try {
            isRecording = false
            cameraProvider?.unbindAll()
            detector.close()
            cameraExecutor.shutdown()
        } catch (_: Exception) {
        }
    }

    @OptIn(ExperimentalGetImage::class)
    @SuppressLint("UnsafeOptInUsageError")
    private fun analyzeFrame(
        imageProxy: ImageProxy,
    ) {
        if (!isRecording) {
            imageProxy.close()
            return
        }

        val nowMs = SystemClock.elapsedRealtime()
        val elapsedMs = nowMs - startedAtMs

        if (elapsedMs - lastProcessedAtMs < processEveryMs) {
            imageProxy.close()
            return
        }

        if (frames.size >= maxFrames) {
            imageProxy.close()
            return
        }

        lastProcessedAtMs = elapsedMs

        val mediaImage = imageProxy.image

        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val image = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees
        )

        detector.process(image)
            .addOnSuccessListener { faces ->
                val frameJson = JSONObject()

                frameJson.put("frame_index", frameIndex)
                frameJson.put("time_ms", elapsedMs)
                frameJson.put("timestamp_ms", System.currentTimeMillis())
                frameJson.put("face_detected", faces.isNotEmpty())
                frameJson.put("face_count", faces.size)

                if (faces.isNotEmpty()) {
                    val face = faces.first()
                    val box = face.boundingBox

                    frameJson.put("head_yaw", face.headEulerAngleY.toDouble())
                    frameJson.put("head_pitch", face.headEulerAngleX.toDouble())
                    frameJson.put("head_roll", face.headEulerAngleZ.toDouble())

                    frameJson.put(
                        "left_eye_open_probability",
                        face.leftEyeOpenProbability?.toDouble()
                    )
                    frameJson.put(
                        "right_eye_open_probability",
                        face.rightEyeOpenProbability?.toDouble()
                    )
                    frameJson.put(
                        "smiling_probability",
                        face.smilingProbability?.toDouble()
                    )
                    val mouthOpenSignal = computeMouthOpenSignal(face)
                    val eyebrowSignal = computeEyebrowSignal(face)

                    frameJson.put(
                        "mouth_open_signal",
                        mouthOpenSignal ?: JSONObject.NULL
                    )

                    frameJson.put(
                        "eyebrow_signal",
                        eyebrowSignal ?: JSONObject.NULL
                    )

                    frameJson.put(
                        "contour_source",
                        "mlkit_face_contours"
                    )

                    val boxJson = JSONObject()
                    boxJson.put("left", box.left)
                    boxJson.put("top", box.top)
                    boxJson.put("right", box.right)
                    boxJson.put("bottom", box.bottom)
                    boxJson.put("width", box.width())
                    boxJson.put("height", box.height())
                    boxJson.put("center_x", box.centerX())
                    boxJson.put("center_y", box.centerY())

                    frameJson.put("bounding_box", boxJson)
                } else {
                    frameJson.put("head_yaw", null)
                    frameJson.put("head_pitch", null)
                    frameJson.put("head_roll", null)
                    frameJson.put("left_eye_open_probability", null)
                    frameJson.put("right_eye_open_probability", null)
                    frameJson.put("smiling_probability", null)
                    frameJson.put("mouth_open_signal", JSONObject.NULL)
                    frameJson.put("eyebrow_signal", JSONObject.NULL)
                    frameJson.put("contour_source", JSONObject.NULL)
                    frameJson.put("bounding_box", null)
                }

                frames.add(frameJson)
                frameIndex += 1
            }
            .addOnFailureListener {
                // Keep recording even if one frame fails.
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }
    private fun computeMouthOpenSignal(face: Face): Double? {
    val upperLipBottom = averagePoint(
        face.getContour(FaceContour.UPPER_LIP_BOTTOM)?.points
    )

    val lowerLipTop = averagePoint(
        face.getContour(FaceContour.LOWER_LIP_TOP)?.points
    )

    val lipPoints = mutableListOf<PointF>()

    face.getContour(FaceContour.UPPER_LIP_TOP)?.points?.let {
        lipPoints.addAll(it)
    }

    face.getContour(FaceContour.UPPER_LIP_BOTTOM)?.points?.let {
        lipPoints.addAll(it)
    }

    face.getContour(FaceContour.LOWER_LIP_TOP)?.points?.let {
        lipPoints.addAll(it)
    }

    face.getContour(FaceContour.LOWER_LIP_BOTTOM)?.points?.let {
        lipPoints.addAll(it)
    }

    if (upperLipBottom == null || lowerLipTop == null || lipPoints.isEmpty()) {
        return null
    }

    val minX = lipPoints.minOf { it.x }
    val maxX = lipPoints.maxOf { it.x }

    val mouthWidth = maxX - minX

    if (mouthWidth <= 1f) {
        return null
    }

    val mouthHeight = distance(
        upperLipBottom,
        lowerLipTop
    )

    return mouthHeight / mouthWidth.toDouble()
}

private fun computeEyebrowSignal(face: Face): Double? {
    val leftEye = averagePoint(
        face.getContour(FaceContour.LEFT_EYE)?.points
    )

    val rightEye = averagePoint(
        face.getContour(FaceContour.RIGHT_EYE)?.points
    )

    val leftEyebrow = averagePoint(
        face.getContour(FaceContour.LEFT_EYEBROW_BOTTOM)?.points
    )

    val rightEyebrow = averagePoint(
        face.getContour(FaceContour.RIGHT_EYEBROW_BOTTOM)?.points
    )

    if (
        leftEye == null ||
        rightEye == null ||
        leftEyebrow == null ||
        rightEyebrow == null
    ) {
        return null
    }

    val interEyeDistance = distance(
        leftEye,
        rightEye
    )

    if (interEyeDistance <= 1.0) {
        return null
    }

    val leftGap = distance(
        leftEyebrow,
        leftEye
    )

    val rightGap = distance(
        rightEyebrow,
        rightEye
    )

    val averageBrowEyeGap = (leftGap + rightGap) / 2.0

    return averageBrowEyeGap / interEyeDistance
}

private fun averagePoint(points: List<PointF>?): PointF? {
    if (points.isNullOrEmpty()) {
        return null
    }

    val averageX = points.map { it.x }.average().toFloat()
    val averageY = points.map { it.y }.average().toFloat()

    return PointF(
        averageX,
        averageY
    )
}

private fun distance(
    first: PointF,
    second: PointF,
): Double {
    val dx = first.x - second.x
    val dy = first.y - second.y

    return sqrt(
        dx.toDouble().pow(2.0) + dy.toDouble().pow(2.0)
    )
}
    private fun buildSummary(): JSONObject {
        val summary = JSONObject()

        val validFaceFrames = frames.count {
            it.optBoolean("face_detected", false)
        }

        val totalFrames = frames.size

        val facePresenceRatio = if (totalFrames == 0) {
            0.0
        } else {
            validFaceFrames.toDouble() / totalFrames.toDouble()
        }

        summary.put("total_frame_count", totalFrames)
        summary.put("valid_face_frame_count", validFaceFrames)
        summary.put("face_presence_ratio", facePresenceRatio)
        summary.put("recording_source", "android_camerax_mlkit_front_camera")
        summary.put("measurement_note", "Mobile native proxy signals for Python-style framewise logs")

        return summary
    }

    private fun JSONObject.toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = keys()

        while (keys.hasNext()) {
            val key = keys.next()
            val value = get(key)

            map[key] = when (value) {
                is JSONObject -> value.toMap()
                is JSONArray -> value.toList()
                JSONObject.NULL -> null
                else -> value
            }
        }

        return map
    }

    private fun JSONArray.toList(): List<Any?> {
        val list = mutableListOf<Any?>()

        for (i in 0 until length()) {
            val value = get(i)

            list.add(
                when (value) {
                    is JSONObject -> value.toMap()
                    is JSONArray -> value.toList()
                    JSONObject.NULL -> null
                    else -> value
                }
            )
        }

        return list
    }
}