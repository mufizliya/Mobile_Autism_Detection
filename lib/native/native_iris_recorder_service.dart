import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../session/session_service.dart';

class NativeIrisRecorderService {
  static const MethodChannel _channel = MethodChannel(
    'native_iris_recorder',
  );

  static const String outputFileName = 'iris_landmark_probe.json';

  static Future<bool> requestCameraPermission() async {
    final PermissionStatus status = await Permission.camera.request();

    return status.isGranted;
  }

  static Future<void> start() async {
    final bool granted = await requestCameraPermission();

    if (!granted) {
      throw Exception('Camera permission denied');
    }

    await _channel.invokeMethod<bool>('start');
  }

  static Future<Map<String, dynamic>> stopAndSave({
    required Directory sessionDir,
  }) async {
    final dynamic result = await _channel.invokeMethod<dynamic>('stop');

    final Map<String, dynamic> payload =
        Map<String, dynamic>.from(result as Map);

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: outputFileName,
      data: payload,
    );

    return payload;
  }
}