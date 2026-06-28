package com.example.autism_detection_mobile_replica

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "native_face_recorder"
    private var recorder: NativeFaceRecorder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        recorder = NativeFaceRecorder(this)

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
    }

    override fun onDestroy() {
        recorder?.shutdown()
        super.onDestroy()
    }
}