import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../session/session_file_names.dart';
import '../session/session_service.dart';

class NativeFaceRecorderService {
  static const MethodChannel _channel = MethodChannel(
    'native_face_recorder',
  );

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
      fileName: SessionFileNames.framewiseFaceSignals,
      data: payload,
    );

    await SessionService.updateJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'updated_at': DateTime.now().toIso8601String(),
        'files': {
          SessionFileNames.childInfo: true,
          SessionFileNames.scqResults: true,
          SessionFileNames.stimulusProtocolSummary: true,
          SessionFileNames.stimulusEvents: true,
          SessionFileNames.videoTest: true,
          SessionFileNames.parentNameCallCues: true,
          SessionFileNames.framewiseFaceSignals: true,
        },
        'framewise_face_signals_summary': payload['summary'],
      },
    );

    return payload;
  }
}