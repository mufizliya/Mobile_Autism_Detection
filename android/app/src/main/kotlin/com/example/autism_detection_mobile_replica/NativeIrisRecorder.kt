package com.example.autism_detection_mobile_replica

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs

class NativeIrisRecorder(
    private val context: Context
) {
    private val cameraExecutor: ExecutorService =
        Executors.newSingleThreadExecutor()

    private var cameraProvider: ProcessCameraProvider? = null
    private var faceLandmarker: FaceLandmarker? = null

    private var isRecording = false
    private var startedAtMs = 0L
    private var lastProcessedAtMs = 0L
    private var frameIndex = 0

    private val processEveryMs = 500L
    private val maxFrames = 120

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
                    onError(e.message ?: "Unable to start native iris recorder")
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

            val payload = mapOf(
                "schema_version" to "mobile_native_iris_landmark_probe_v1",
                "generated_at" to System.currentTimeMillis(),
                "sample_interval_ms" to processEveryMs,
                "frame_count" to frames.size,
                "summary" to buildSummary().toMap(),
                "frames" to frames.map { it.toMap() },
            )

            onSuccess(payload)
        } catch (e: Exception) {
            onError(e.message ?: "Unable to stop native iris recorder")
        }
    }

    fun shutdown() {
        try {
            isRecording = false
            cameraProvider?.unbindAll()
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
            .setMinTrackingConfidence(0.3f)
            .setMinFacePresenceConfidence(0.3f)
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

        try {
            val bitmap = imageProxyToBitmap(imageProxy)
            val rotatedBitmap = rotateBitmap(
                bitmap,
                imageProxy.imageInfo.rotationDegrees.toFloat()
            )
            val debugImageJson = JSONObject()
debugImageJson.put("image_proxy_width", imageProxy.width)
debugImageJson.put("image_proxy_height", imageProxy.height)
debugImageJson.put("rotation_degrees", imageProxy.imageInfo.rotationDegrees)
debugImageJson.put("bitmap_width", bitmap.width)
debugImageJson.put("bitmap_height", bitmap.height)
debugImageJson.put("rotated_bitmap_width", rotatedBitmap.width)
debugImageJson.put("rotated_bitmap_height", rotatedBitmap.height)

            val mpImage = BitmapImageBuilder(rotatedBitmap).build()
            val result = faceLandmarker?.detect(mpImage)

            val frameJson = JSONObject()

            frameJson.put("frame_index", frameIndex)
            frameJson.put("time_ms", elapsedMs)
            frameJson.put("timestamp_ms", System.currentTimeMillis())
            frameJson.put("debug_image", debugImageJson)

            val landmarksList = result?.faceLandmarks()

            frameJson.put(
                "face_detected",
                landmarksList != null && landmarksList.isNotEmpty()
            )

            frameJson.put(
                "face_count",
                landmarksList?.size ?: 0
            )

            if (landmarksList != null && landmarksList.isNotEmpty()) {
                val landmarks = landmarksList[0]

                val irisJson = buildIrisSignalsJson(landmarks)

                frameJson.put("iris_signals", irisJson)
                frameJson.put("landmark_count", landmarks.size)
                frameJson.put("landmark_source", "mediapipe_face_landmarker")
            } else {
                frameJson.put("iris_signals", JSONObject.NULL)
                frameJson.put("landmark_count", 0)
                frameJson.put("landmark_source", JSONObject.NULL)
            }

            frames.add(frameJson)
            frameIndex += 1
        } catch (e: Exception) {
            val frameJson = JSONObject()
            frameJson.put("frame_index", frameIndex)
            frameJson.put("time_ms", elapsedMs)
            frameJson.put("timestamp_ms", System.currentTimeMillis())
            frameJson.put("face_detected", false)
            frameJson.put("face_count", 0)
            frameJson.put("error", e.message ?: "iris frame processing failed")

            frames.add(frameJson)
            frameIndex += 1
        } finally {
            imageProxy.close()
        }
    }

    private fun buildIrisSignalsJson(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>
    ): JSONObject {
        val json = JSONObject()

        /*
         * MediaPipe Face Mesh / Face Landmarker commonly uses:
         * left iris: 468, 469, 470, 471, 472
         * right iris: 473, 474, 475, 476, 477
         *
         * If the task model returns only 468 landmarks, iris landmarks are unavailable.
         */
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

        /*
         * Approx eye corner indices from Face Mesh topology:
         * left eye corners: 33 and 133
         * right eye corners: 362 and 263
         */
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

        return json
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

    val yuvImage = android.graphics.YuvImage(
        nv21,
        android.graphics.ImageFormat.NV21,
        imageProxy.width,
        imageProxy.height,
        null
    )

    val out = java.io.ByteArrayOutputStream()

    yuvImage.compressToJpeg(
        android.graphics.Rect(
            0,
            0,
            imageProxy.width,
            imageProxy.height
        ),
        90,
        out
    )

    val imageBytes = out.toByteArray()

    return android.graphics.BitmapFactory.decodeByteArray(
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

    private fun buildSummary(): JSONObject {
        val summary = JSONObject()

        val validFaceFrames = frames.count {
            it.optBoolean("face_detected", false)
        }

        val irisFrames = frames.count {
            val iris = it.optJSONObject("iris_signals")
            iris?.optBoolean("has_iris_landmarks", false) == true
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
        summary.put("recording_source", "mediapipe_face_landmarker_front_camera")
        summary.put(
            "measurement_note",
            "Proof-of-concept iris/eye landmark extraction for calibrated gaze estimation"
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