package com.example.autism_detection_mobile_replica

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.PointF
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
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

    private var faceLandmarker: FaceLandmarker? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var isRecording = false
    private var startedAtMs = 0L
    private var lastProcessedAtMs = 0L
    private var frameIndex = 0

    private val processEveryMs = 200L
    private val maxFrames = 1000

    private val frames = mutableListOf<JSONObject>()

    fun start(
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        if (isRecording) {
            onSuccess()
            return
        }

        try {
            setupFaceLandmarker()
        } catch (e: Exception) {
            onError(e.message ?: "Unable to initialize MediaPipe Face Landmarker")
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
                "schema_version" to "mobile_native_framewise_face_signals_v2_with_mediapipe_iris",
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
            faceLandmarker?.close()
            cameraExecutor.shutdown()
        } catch (_: Exception) {
        }
    }

    private fun setupFaceLandmarker() {
        if (faceLandmarker != null) {
            return
        }

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("face_landmarker.task")
            .build()

        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.3f)
            .setMinFacePresenceConfidence(0.3f)
            .setMinTrackingConfidence(0.3f)
            .build()

        faceLandmarker = FaceLandmarker.createFromOptions(
            context,
            options
        )
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

        val irisSignals = try {
            detectIrisSignals(imageProxy)
        } catch (e: Exception) {
            val errorJson = JSONObject()
            errorJson.put("has_iris_landmarks", false)
            errorJson.put("landmark_count", 0)
            errorJson.put("error", e.message ?: "MediaPipe iris extraction failed")
            errorJson
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
                frameJson.put("iris_signals", irisSignals)
                frameJson.put(
                    "has_iris_landmarks",
                    irisSignals.optBoolean("has_iris_landmarks", false)
                )
                frameJson.put(
                    "iris_landmark_count",
                    irisSignals.optInt("landmark_count", 0)
                )
                frameJson.put("iris_source", "mediapipe_face_landmarker")

                copyIrisSignalToTopLevel(
                    frameJson = frameJson,
                    irisSignals = irisSignals,
                )

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
                    frameJson.put("head_yaw", JSONObject.NULL)
                    frameJson.put("head_pitch", JSONObject.NULL)
                    frameJson.put("head_roll", JSONObject.NULL)
                    frameJson.put("left_eye_open_probability", JSONObject.NULL)
                    frameJson.put("right_eye_open_probability", JSONObject.NULL)
                    frameJson.put("smiling_probability", JSONObject.NULL)
                    frameJson.put("mouth_open_signal", JSONObject.NULL)
                    frameJson.put("eyebrow_signal", JSONObject.NULL)
                    frameJson.put("contour_source", JSONObject.NULL)
                    frameJson.put("bounding_box", JSONObject.NULL)
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

    private fun detectIrisSignals(
        imageProxy: ImageProxy,
    ): JSONObject {
        val bitmap = imageProxyToBitmap(imageProxy)
        val rotatedBitmap = rotateBitmap(
            bitmap,
            imageProxy.imageInfo.rotationDegrees.toFloat()
        )

        val mpImage = BitmapImageBuilder(rotatedBitmap).build()
        val result = faceLandmarker?.detect(mpImage)
        val landmarksList = result?.faceLandmarks()

        if (landmarksList == null || landmarksList.isEmpty()) {
            val json = JSONObject()
            json.put("has_iris_landmarks", false)
            json.put("landmark_count", 0)
            return json
        }

        return buildIrisSignalsJson(landmarksList[0])
    }

    private fun buildIrisSignalsJson(
        landmarks: List<NormalizedLandmark>,
    ): JSONObject {
        val json = JSONObject()
        val hasIris = landmarks.size >= 478

        json.put("has_iris_landmarks", hasIris)
        json.put("landmark_count", landmarks.size)

        if (!hasIris) {
            json.put("left_iris_center_x", JSONObject.NULL)
            json.put("left_iris_center_y", JSONObject.NULL)
            json.put("right_iris_center_x", JSONObject.NULL)
            json.put("right_iris_center_y", JSONObject.NULL)
            json.put("left_iris_in_eye_x", JSONObject.NULL)
            json.put("right_iris_in_eye_x", JSONObject.NULL)
            json.put("average_iris_in_eye_x", JSONObject.NULL)
            json.put("iris_balance_abs_diff", JSONObject.NULL)
            json.put("left_mediapipe_ear", JSONObject.NULL)
            json.put("right_mediapipe_ear", JSONObject.NULL)
            json.put("average_mediapipe_ear", JSONObject.NULL)
            json.put("mediapipe_eye_open_signal", JSONObject.NULL)
            return json
        }

        val leftIris = listOf(468, 469, 470, 471, 472).map {
            landmarks[it]
        }

        val rightIris = listOf(473, 474, 475, 476, 477).map {
            landmarks[it]
        }

        val leftIrisX = leftIris.map { it.x() }.average()
        val leftIrisY = leftIris.map { it.y() }.average()

        val rightIrisX = rightIris.map { it.x() }.average()
        val rightIrisY = rightIris.map { it.y() }.average()

        val leftEyeOuter = landmarks[33]
        val leftEyeInner = landmarks[133]
        val rightEyeInner = landmarks[362]
        val rightEyeOuter = landmarks[263]

        val leftEyeMinX = minOf(leftEyeOuter.x(), leftEyeInner.x())
        val leftEyeMaxX = maxOf(leftEyeOuter.x(), leftEyeInner.x())
        val rightEyeMinX = minOf(rightEyeInner.x(), rightEyeOuter.x())
        val rightEyeMaxX = maxOf(rightEyeInner.x(), rightEyeOuter.x())

        val leftIrisInEyeX = normalizeSafe(
            leftIrisX,
            leftEyeMinX.toDouble(),
            leftEyeMaxX.toDouble()
        )

        val rightIrisInEyeX = normalizeSafe(
            rightIrisX,
            rightEyeMinX.toDouble(),
            rightEyeMaxX.toDouble()
        )

        json.put("left_iris_center_x", round4(leftIrisX))
        json.put("left_iris_center_y", round4(leftIrisY))
        json.put("right_iris_center_x", round4(rightIrisX))
        json.put("right_iris_center_y", round4(rightIrisY))
        json.put("left_iris_in_eye_x", round4(leftIrisInEyeX))
        json.put("right_iris_in_eye_x", round4(rightIrisInEyeX))
        json.put(
            "average_iris_in_eye_x",
            round4((leftIrisInEyeX + rightIrisInEyeX) / 2.0)
        )
        json.put(
            "iris_balance_abs_diff",
            round4(abs(leftIrisInEyeX - rightIrisInEyeX))
        )

        val leftEar = computeEyeAspectRatio(
            landmarks = landmarks,
            indices = listOf(33, 160, 158, 133, 153, 144)
        )

        val rightEar = computeEyeAspectRatio(
            landmarks = landmarks,
            indices = listOf(362, 385, 387, 263, 373, 380)
        )

        val averageEar = if (leftEar != null && rightEar != null) {
            (leftEar + rightEar) / 2.0
        } else {
            null
        }

        json.put("left_mediapipe_ear", leftEar?.let { round4(it) } ?: JSONObject.NULL)
        json.put("right_mediapipe_ear", rightEar?.let { round4(it) } ?: JSONObject.NULL)
        json.put("average_mediapipe_ear", averageEar?.let { round4(it) } ?: JSONObject.NULL)
        json.put("mediapipe_eye_open_signal", averageEar?.let { round4(it) } ?: JSONObject.NULL)

        return json
    }

    private fun copyIrisSignalToTopLevel(
        frameJson: JSONObject,
        irisSignals: JSONObject,
    ) {
        val keysToCopy = listOf(
            "left_iris_center_x",
            "left_iris_center_y",
            "right_iris_center_x",
            "right_iris_center_y",
            "left_iris_in_eye_x",
            "right_iris_in_eye_x",
            "average_iris_in_eye_x",
            "iris_balance_abs_diff",
            "left_mediapipe_ear",
            "right_mediapipe_ear",
            "average_mediapipe_ear",
            "mediapipe_eye_open_signal",
        )

        for (key in keysToCopy) {
            frameJson.put(key, irisSignals.opt(key) ?: JSONObject.NULL)
        }
    }

    private fun computeEyeAspectRatio(
        landmarks: List<NormalizedLandmark>,
        indices: List<Int>,
    ): Double? {
        if (indices.size != 6) {
            return null
        }

        if (indices.any { it < 0 || it >= landmarks.size }) {
            return null
        }

        val p1 = landmarks[indices[0]]
        val p2 = landmarks[indices[1]]
        val p3 = landmarks[indices[2]]
        val p4 = landmarks[indices[3]]
        val p5 = landmarks[indices[4]]
        val p6 = landmarks[indices[5]]

        val horizontal = landmarkDistance(p1, p4)

        if (horizontal <= 0.000001) {
            return null
        }

        val verticalA = landmarkDistance(p2, p6)
        val verticalB = landmarkDistance(p3, p5)

        return (verticalA + verticalB) / (2.0 * horizontal)
    }

    private fun landmarkDistance(
        first: NormalizedLandmark,
        second: NormalizedLandmark,
    ): Double {
        val dx = first.x() - second.x()
        val dy = first.y() - second.y()
        val dz = first.z() - second.z()

        return sqrt(
            dx.toDouble().pow(2.0) +
                dy.toDouble().pow(2.0) +
                dz.toDouble().pow(2.0)
        )
    }

    private fun normalizeSafe(
        value: Double,
        min: Double,
        max: Double,
    ): Double {
        if (max - min <= 0.000001) {
            return 0.5
        }

        return (value - min) / (max - min)
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
        val nv21 = yuv420888ToNv21(imageProxy)

        val yuvImage = YuvImage(
            nv21,
            ImageFormat.NV21,
            imageProxy.width,
            imageProxy.height,
            null
        )

        val out = ByteArrayOutputStream()

        yuvImage.compressToJpeg(
            Rect(0, 0, imageProxy.width, imageProxy.height),
            90,
            out
        )

        val imageBytes = out.toByteArray()

        return BitmapFactory.decodeByteArray(
            imageBytes,
            0,
            imageBytes.size
        )
    }

    private fun yuv420888ToNv21(imageProxy: ImageProxy): ByteArray {
        val width = imageProxy.width
        val height = imageProxy.height

        val yPlane = imageProxy.planes[0]
        val uPlane = imageProxy.planes[1]
        val vPlane = imageProxy.planes[2]

        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val nv21 = ByteArray(width * height * 3 / 2)

        var outputOffset = 0

        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride

        for (row in 0 until height) {
            for (col in 0 until width) {
                val yIndex = row * yRowStride + col * yPixelStride
                nv21[outputOffset++] = yBuffer.get(yIndex)
            }
        }

        val chromaHeight = height / 2
        val chromaWidth = width / 2

        val uRowStride = uPlane.rowStride
        val uPixelStride = uPlane.pixelStride

        val vRowStride = vPlane.rowStride
        val vPixelStride = vPlane.pixelStride

        for (row in 0 until chromaHeight) {
            for (col in 0 until chromaWidth) {
                val vIndex = row * vRowStride + col * vPixelStride
                val uIndex = row * uRowStride + col * uPixelStride

                nv21[outputOffset++] = vBuffer.get(vIndex)
                nv21[outputOffset++] = uBuffer.get(uIndex)
            }
        }

        return nv21
    }

    private fun rotateBitmap(
        bitmap: Bitmap,
        degrees: Float,
    ): Bitmap {
        if (degrees == 0f) {
            return bitmap
        }

        val matrix = Matrix()
        matrix.postRotate(degrees)

        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true
        )
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

        val irisFrames = frames.count {
            it.optBoolean("has_iris_landmarks", false)
        }

        val totalFrames = frames.size

        val facePresenceRatio = if (totalFrames == 0) {
            0.0
        } else {
            validFaceFrames.toDouble() / totalFrames.toDouble()
        }

        val irisPresenceRatio = if (totalFrames == 0) {
            0.0
        } else {
            irisFrames.toDouble() / totalFrames.toDouble()
        }

        summary.put("total_frame_count", totalFrames)
        summary.put("valid_face_frame_count", validFaceFrames)
        summary.put("iris_landmark_frame_count", irisFrames)
        summary.put("face_presence_ratio", facePresenceRatio)
        summary.put("iris_presence_ratio", irisPresenceRatio)
        summary.put("recording_source", "android_camerax_mlkit_and_mediapipe_front_camera")
        summary.put("sample_interval_ms", processEveryMs)
        summary.put("max_frames", maxFrames)
        summary.put(
            "measurement_note",
            "Unified native recorder: ML Kit face/head/contour signals plus MediaPipe iris landmarks and MediaPipe eyelid EAR from one CameraX stream"
        )

        return summary
    }

    private fun round4(value: Double): Double {
        return String.format("%.4f", value).toDouble()
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
