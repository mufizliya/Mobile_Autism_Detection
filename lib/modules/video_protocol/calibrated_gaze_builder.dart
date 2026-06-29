import 'dart:io';
import 'dart:math';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';

class CalibratedGazeBuilder {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final Map<String, dynamic>? calibration =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.gazeCalibration,
    );

    final Map<String, dynamic>? irisSignals =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.videoIrisSignals,
    );

    if (calibration == null || irisSignals == null) {
      final Map<String, dynamic> emptyPayload = {
        'schema_version': 'mobile_calibrated_iris_gaze_v1',
        'generated_at': DateTime.now().toIso8601String(),
        'status': 'missing_inputs',
        'reason': 'Missing gaze calibration or video iris signal file.',
        'frames': [],
      };

      await SessionService.saveJson(
        sessionDir: sessionDir,
        fileName: SessionFileNames.calibratedGazeFrames,
        data: emptyPayload,
      );

      return emptyPayload;
    }

    final Map<String, dynamic> mapping =
        calibration['mapping'] is Map
            ? Map<String, dynamic>.from(calibration['mapping'] as Map)
            : <String, dynamic>{};

    final Map<String, dynamic> gazeXMapping =
        mapping['gaze_x'] is Map
            ? Map<String, dynamic>.from(mapping['gaze_x'] as Map)
            : <String, dynamic>{};

    final Map<String, dynamic> gazeYMapping =
        mapping['gaze_y'] is Map
            ? Map<String, dynamic>.from(mapping['gaze_y'] as Map)
            : <String, dynamic>{};

    final String gazeXInput =
        gazeXMapping['input']?.toString() ?? 'average_iris_in_eye_x';

    final String gazeYInput =
        gazeYMapping['input']?.toString() ?? 'mean_iris_center_y';

    final double? xIntercept = nullableNumber(gazeXMapping['intercept']);
    final double? xSlope = nullableNumber(gazeXMapping['slope']);
    final double? yIntercept = nullableNumber(gazeYMapping['intercept']);
    final double? ySlope = nullableNumber(gazeYMapping['slope']);

    final List<Map<String, dynamic>> rawFrames = listMap(
      irisSignals['frames'],
    );

    final List<Map<String, dynamic>> calibratedFrames = [];

    int validGazeCount = 0;

    for (final Map<String, dynamic> frame in rawFrames) {
      final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

      final double? xInput = extractInput(
        inputName: gazeXInput,
        iris: iris,
      );

      final double? yInput = extractInput(
        inputName: gazeYInput,
        iris: iris,
      );

      double? gazeX;
      double? gazeY;

      if (xInput != null &&
          yInput != null &&
          xIntercept != null &&
          xSlope != null &&
          yIntercept != null &&
          ySlope != null) {
        gazeX = clamp01(xIntercept + xSlope * xInput);
        gazeY = clamp01(yIntercept + ySlope * yInput);
        validGazeCount += 1;
      }

      calibratedFrames.add({
        'frame_index': frame['frame_index'],
        'time_ms': frame['time_ms'],
        'timestamp_ms': frame['timestamp_ms'],
        'face_detected': frame['face_detected'],
        'has_iris_landmarks': iris?['has_iris_landmarks'] == true,
        'gaze_x': gazeX == null ? null : round4(gazeX),
        'gaze_y': gazeY == null ? null : round4(gazeY),
        'gaze_valid': gazeX != null && gazeY != null,
        'gaze_x_input_name': gazeXInput,
        'gaze_y_input_name': gazeYInput,
        'gaze_x_input_value': xInput == null ? null : round4(xInput),
        'gaze_y_input_value': yInput == null ? null : round4(yInput),
        'source': 'mobile_iris_landmark_calibrated_gaze',
      });
    }

    final double validRatio = calibratedFrames.isEmpty
        ? 0.0
        : validGazeCount / calibratedFrames.length;

    final Map<String, dynamic> payload = {
      'schema_version': 'mobile_calibrated_iris_gaze_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'status': validGazeCount > 0 ? 'computed' : 'no_valid_gaze_frames',
      'calibration_file': SessionFileNames.gazeCalibration,
      'video_iris_file': SessionFileNames.videoIrisSignals,
      'frame_count': calibratedFrames.length,
      'valid_gaze_frame_count': validGazeCount,
      'valid_gaze_ratio': round4(validRatio),
      'mapping': {
        'gaze_x': gazeXMapping,
        'gaze_y': gazeYMapping,
      },
      'frames': calibratedFrames,
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.calibratedGazeFrames,
      data: payload,
    );

    return payload;
  }

  static double? extractInput({
    required String inputName,
    required Map<String, dynamic>? iris,
  }) {
    if (iris == null) return null;

    if (inputName == 'mean_average_iris_in_eye_x' ||
        inputName == 'average_iris_in_eye_x') {
      return nullableNumber(iris['average_iris_in_eye_x']);
    }

    if (inputName == 'mean_iris_center_x') {
      final double? leftX = nullableNumber(iris['left_iris_center_x']);
      final double? rightX = nullableNumber(iris['right_iris_center_x']);

      if (leftX == null || rightX == null) return null;

      return (leftX + rightX) / 2.0;
    }

    if (inputName == 'mean_iris_center_y') {
      final double? leftY = nullableNumber(iris['left_iris_center_y']);
      final double? rightY = nullableNumber(iris['right_iris_center_y']);

      if (leftY == null || rightY == null) return null;

      return (leftY + rightY) / 2.0;
    }

    return nullableNumber(iris[inputName]);
  }

  static List<Map<String, dynamic>> listMap(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Map<String, dynamic>? mapOrNull(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  static double? nullableNumber(dynamic value) {
    if (value is num) return value.toDouble();

    if (value is String) return double.tryParse(value);

    return null;
  }

  static double clamp01(double value) {
    return max(0.0, min(1.0, value));
  }

  static double round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }
}