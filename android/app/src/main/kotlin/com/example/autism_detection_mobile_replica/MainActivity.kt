package com.example.autism_detection_mobile_replica

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "native_face_recorder"
    private var recorder: NativeFaceRecorder? = null
    private var irisRecorder: NativeIrisRecorder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        recorder = NativeFaceRecorder(this)
        irisRecorder = NativeIrisRecorder(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    recorder?.start(
                        onSuccess = {
                            result.success(true)
                        },
                        onError = { message ->
                            result.error("START_FAILED", message, null)
                        }
                    )
                }

                "stop" -> {
                    recorder?.stop(
                        onSuccess = { payload ->
                            result.success(payload)
                        },
                        onError = { message ->
                            result.error("STOP_FAILED", message, null)
                        }
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
    flutterEngine.dartExecutor.binaryMessenger,
    "native_iris_recorder"
).setMethodCallHandler { call, result ->
    when (call.method) {
        "start" -> {
            irisRecorder?.start(
                onSuccess = {
                    result.success(true)
                },
                onError = { message ->
                    result.error("IRIS_START_FAILED", message, null)
                }
            )
        }

        "stop" -> {
            irisRecorder?.stop(
                onSuccess = { payload ->
                    result.success(payload)
                },
                onError = { message ->
                    result.error("IRIS_STOP_FAILED", message, null)
                }
            )
        }

        else -> {
            result.notImplemented()
        }
    }
}
    }

    override fun onDestroy() {
        recorder?.shutdown()
        irisRecorder?.shutdown()
        super.onDestroy()
    }
}