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

    final Map<String, dynamic>? framewiseSignals =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.framewiseFaceSignals,
    );

    if (calibration == null || framewiseSignals == null) {
      final Map<String, dynamic> emptyPayload = {
        'schema_version': 'mobile_calibrated_iris_gaze_v3',
        'generated_at': DateTime.now().toIso8601String(),
        'status': 'missing_inputs',
        'reason':
            'Missing gaze calibration or unified framewise face signal file.',
        'frames': [],
      };

      await SessionService.saveJson(
        sessionDir: sessionDir,
        fileName: SessionFileNames.calibratedGazeFrames,
        data: emptyPayload,
      );

      return emptyPayload;
    }

    final Map<String, dynamic> mapping = calibration['mapping'] is Map
        ? Map<String, dynamic>.from(calibration['mapping'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> gazeXMapping = mapping['gaze_x'] is Map
        ? Map<String, dynamic>.from(mapping['gaze_x'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> gazeYMapping = mapping['gaze_y'] is Map
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
      framewiseSignals['frames'],
    );

    final List<Map<String, dynamic>> interimFrames = [];

    int validGazeCount = 0;
    int irisFrameCount = 0;

    for (final Map<String, dynamic> frame in rawFrames) {
      final bool hasIris = frame['has_iris_landmarks'] == true;

      if (hasIris) {
        irisFrameCount += 1;
      }

      final double? xInput = extractInput(
        inputName: gazeXInput,
        frame: frame,
      );

      final double? yInput = extractInput(
        inputName: gazeYInput,
        frame: frame,
      );

      double? rawGazeX;
      double? rawGazeY;

      if (hasIris &&
          xInput != null &&
          yInput != null &&
          xIntercept != null &&
          xSlope != null &&
          yIntercept != null &&
          ySlope != null) {
        rawGazeX = xIntercept + xSlope * xInput;
        rawGazeY = yIntercept + ySlope * yInput;
        validGazeCount += 1;
      }

      interimFrames.add({
        'frame_index': frame['frame_index'],
        'time_ms': frame['time_ms'],
        'timestamp_ms': frame['timestamp_ms'],
        'face_detected': frame['face_detected'],
        'has_iris_landmarks': hasIris,
        'raw_gaze_x': rawGazeX,
        'raw_gaze_y': rawGazeY,
        'gaze_x_input_name': gazeXInput,
        'gaze_y_input_name': gazeYInput,
        'gaze_x_input_value': xInput,
        'gaze_y_input_value': yInput,
      });
    }

    final Map<String, dynamic> preStabilizationClipping =
        clippingStatsFromRaw(
      frames: interimFrames,
      rawXKey: 'raw_gaze_x',
      rawYKey: 'raw_gaze_y',
    );

    final double preYClippedRatio =
        nullableNumber(preStabilizationClipping['y_clipped_ratio']) ?? 0.0;

    final List<double> rawYValues = interimFrames
        .map((Map<String, dynamic> frame) => nullableNumber(frame['raw_gaze_y']))
        .whereType<double>()
        .toList();

    final bool shouldStabilizeY =
        rawYValues.length >= 20 && preYClippedRatio > 0.50;

    String gazeYMappingMode = 'linear_calibration';

    double? yP05;
    double? yP95;

    if (shouldStabilizeY) {
      yP05 = percentile(rawYValues, 0.05);
      yP95 = percentile(rawYValues, 0.95);

      if (yP05 != null && yP95 != null && (yP95 - yP05).abs() >= 0.05) {
        gazeYMappingMode = 'video_percentile_stabilized_y';
      } else {
        gazeYMappingMode = 'linear_calibration';
      }
    }

    final List<Map<String, dynamic>> calibratedFrames = [];

    int xClippedCount = 0;
    int yClippedCount = 0;
    int anyClippedCount = 0;

    for (final Map<String, dynamic> frame in interimFrames) {
      final double? rawGazeX = nullableNumber(frame['raw_gaze_x']);
      final double? rawGazeY = nullableNumber(frame['raw_gaze_y']);

      double? gazeX;
      double? gazeY;

      bool xClipped = false;
      bool yClipped = false;

      if (rawGazeX != null && rawGazeY != null) {
        xClipped = rawGazeX < 0.0 || rawGazeX > 1.0;
        gazeX = clamp01(rawGazeX);

        if (gazeYMappingMode == 'video_percentile_stabilized_y' &&
            yP05 != null &&
            yP95 != null) {
          final double stabilizedRawY =
              0.08 + ((rawGazeY - yP05) / (yP95 - yP05)) * 0.84;

          yClipped = stabilizedRawY < 0.0 || stabilizedRawY > 1.0;
          gazeY = clamp01(stabilizedRawY);

          frame['stabilized_raw_gaze_y'] = stabilizedRawY;
          frame['stabilization_y_p05'] = yP05;
          frame['stabilization_y_p95'] = yP95;
        } else {
          yClipped = rawGazeY < 0.0 || rawGazeY > 1.0;
          gazeY = clamp01(rawGazeY);
        }

        if (xClipped) {
          xClippedCount += 1;
        }

        if (yClipped) {
          yClippedCount += 1;
        }

        if (xClipped || yClipped) {
          anyClippedCount += 1;
        }
      }

      calibratedFrames.add({
        'frame_index': frame['frame_index'],
        'time_ms': frame['time_ms'],
        'timestamp_ms': frame['timestamp_ms'],
        'face_detected': frame['face_detected'],
        'has_iris_landmarks': frame['has_iris_landmarks'],
        'gaze_x': gazeX == null ? null : round4(gazeX),
        'gaze_y': gazeY == null ? null : round4(gazeY),
        'raw_gaze_x': rawGazeX == null ? null : round4(rawGazeX),
        'raw_gaze_y': rawGazeY == null ? null : round4(rawGazeY),
        'stabilized_raw_gaze_y': frame['stabilized_raw_gaze_y'] == null
            ? null
            : round4(nullableNumber(frame['stabilized_raw_gaze_y'])!),
        'gaze_x_clipped': xClipped,
        'gaze_y_clipped': yClipped,
        'any_gaze_clipped': xClipped || yClipped,
        'gaze_valid': gazeX != null && gazeY != null,
        'gaze_x_input_name': frame['gaze_x_input_name'],
        'gaze_y_input_name': frame['gaze_y_input_name'],
        'gaze_x_input_value': frame['gaze_x_input_value'] == null
            ? null
            : round4(nullableNumber(frame['gaze_x_input_value'])!),
        'gaze_y_input_value': frame['gaze_y_input_value'] == null
            ? null
            : round4(nullableNumber(frame['gaze_y_input_value'])!),
        'gaze_y_mapping_mode': gazeYMappingMode,
        'source': 'mobile_unified_recorder_iris_calibrated_gaze',
      });
    }

    final double validRatio = calibratedFrames.isEmpty
        ? 0.0
        : validGazeCount / calibratedFrames.length;

    final double irisRatio = calibratedFrames.isEmpty
        ? 0.0
        : irisFrameCount / calibratedFrames.length;

    final double xClippedRatio =
        validGazeCount == 0 ? 0.0 : xClippedCount / validGazeCount;

    final double yClippedRatio =
        validGazeCount == 0 ? 0.0 : yClippedCount / validGazeCount;

    final double anyClippedRatio =
        validGazeCount == 0 ? 0.0 : anyClippedCount / validGazeCount;

    String gazeClippingStatus = 'valid';

    if (validGazeCount == 0) {
      gazeClippingStatus = 'failed';
    } else if (xClippedRatio > 0.25 || yClippedRatio > 0.50) {
      gazeClippingStatus = 'warning';
    }

    final Map<String, dynamic> payload = {
      'schema_version': 'mobile_calibrated_iris_gaze_v3',
      'generated_at': DateTime.now().toIso8601String(),
      'status': validGazeCount > 0 ? 'computed' : 'no_valid_gaze_frames',
      'calibration_file': SessionFileNames.gazeCalibration,
      'framewise_input_file': SessionFileNames.framewiseFaceSignals,
      'frame_count': calibratedFrames.length,
      'iris_frame_count': irisFrameCount,
      'valid_gaze_frame_count': validGazeCount,
      'iris_frame_ratio': round4(irisRatio),
      'valid_gaze_ratio': round4(validRatio),
      'gaze_y_mapping_mode': gazeYMappingMode,
      'vertical_stabilization': {
        'enabled': gazeYMappingMode == 'video_percentile_stabilized_y',
        'reason':
            'Applied only when raw vertical gaze clipping was high after calibration.',
        'pre_stabilization_y_clipped_ratio':
            preStabilizationClipping['y_clipped_ratio'],
        'raw_y_percentile_05': yP05 == null ? null : round4(yP05),
        'raw_y_percentile_95': yP95 == null ? null : round4(yP95),
        'output_margin': 0.08,
        'method':
            'Map raw_gaze_y p05..p95 to normalized screen range 0.08..0.92.',
      },
      'pre_stabilization_gaze_clipping': preStabilizationClipping,
      'gaze_clipping': {
        'status': gazeClippingStatus,
        'x_clipped_count': xClippedCount,
        'y_clipped_count': yClippedCount,
        'any_clipped_count': anyClippedCount,
        'x_clipped_ratio': round4(xClippedRatio),
        'y_clipped_ratio': round4(yClippedRatio),
        'any_clipped_ratio': round4(anyClippedRatio),
        'rule': {
          'valid': 'x clipped ratio <= 0.25 and y clipped ratio <= 0.50.',
          'warning':
              'One or both gaze axes are frequently clipped to screen edges.',
          'failed': 'No valid calibrated gaze frames were available.',
        },
      },
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

  static Map<String, dynamic> clippingStatsFromRaw({
    required List<Map<String, dynamic>> frames,
    required String rawXKey,
    required String rawYKey,
  }) {
    int validCount = 0;
    int xClippedCount = 0;
    int yClippedCount = 0;
    int anyClippedCount = 0;

    for (final Map<String, dynamic> frame in frames) {
      final double? rawX = nullableNumber(frame[rawXKey]);
      final double? rawY = nullableNumber(frame[rawYKey]);

      if (rawX == null || rawY == null) {
        continue;
      }

      validCount += 1;

      final bool xClipped = rawX < 0.0 || rawX > 1.0;
      final bool yClipped = rawY < 0.0 || rawY > 1.0;

      if (xClipped) {
        xClippedCount += 1;
      }

      if (yClipped) {
        yClippedCount += 1;
      }

      if (xClipped || yClipped) {
        anyClippedCount += 1;
      }
    }

    final double xRatio =
        validCount == 0 ? 0.0 : xClippedCount / validCount;

    final double yRatio =
        validCount == 0 ? 0.0 : yClippedCount / validCount;

    final double anyRatio =
        validCount == 0 ? 0.0 : anyClippedCount / validCount;

    String status = 'valid';

    if (validCount == 0) {
      status = 'failed';
    } else if (xRatio > 0.25 || yRatio > 0.50) {
      status = 'warning';
    }

    return {
      'status': status,
      'valid_count': validCount,
      'x_clipped_count': xClippedCount,
      'y_clipped_count': yClippedCount,
      'any_clipped_count': anyClippedCount,
      'x_clipped_ratio': round4(xRatio),
      'y_clipped_ratio': round4(yRatio),
      'any_clipped_ratio': round4(anyRatio),
    };
  }

  static double? extractInput({
    required String inputName,
    required Map<String, dynamic> frame,
  }) {
    if (inputName == 'mean_average_iris_in_eye_x' ||
        inputName == 'average_iris_in_eye_x') {
      return nullableNumber(frame['average_iris_in_eye_x']);
    }

    if (inputName == 'mean_iris_center_x') {
      final double? leftX = nullableNumber(frame['left_iris_center_x']);
      final double? rightX = nullableNumber(frame['right_iris_center_x']);

      if (leftX == null || rightX == null) return null;

      return (leftX + rightX) / 2.0;
    }

    if (inputName == 'mean_iris_center_y') {
      final double? leftY = nullableNumber(frame['left_iris_center_y']);
      final double? rightY = nullableNumber(frame['right_iris_center_y']);

      if (leftY == null || rightY == null) return null;

      return (leftY + rightY) / 2.0;
    }

    return nullableNumber(frame[inputName]);
  }

  static List<Map<String, dynamic>> listMap(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static double? nullableNumber(dynamic value) {
    if (value is num) return value.toDouble();

    if (value is String) return double.tryParse(value);

    return null;
  }

  static double? percentile(List<double> values, double p) {
    if (values.isEmpty) return null;

    final List<double> sorted = [...values]..sort();

    final double rank = (sorted.length - 1) * p;
    final int lower = rank.floor();
    final int upper = rank.ceil();

    if (lower == upper) {
      return sorted[lower];
    }

    final double weight = rank - lower;

    return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
  }

  static double clamp01(double value) {
    return max(0.0, min(1.0, value));
  }

  static double round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }
}