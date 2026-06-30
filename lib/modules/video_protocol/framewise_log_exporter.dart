import 'dart:io';
import 'dart:math';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';

class FramewiseLogExporter {
  static const List<String> csvHeaders = [
    'timestamp',
    'elapsed_time',
    'stimulus_id',
    'stimulus_type',
    'paper_category',
    'frame_index',
    'face_detected',
    'left_ear',
    'right_ear',
    'avg_ear',
    'eye_open',
    'blink_state',
    'gaze_x',
    'gaze_y',
    'gaze_valid',
    'gaze_source',
    'yaw_proxy',
    'pitch_proxy',
    'roll_proxy_deg',
    'head_center_x',
    'head_center_y',
    'head_movement',
    'head_acceleration',
    'mouth_open',
    'eyebrow_signal',
  ];

  static Future<Map<String, dynamic>> exportPerStimulusLogs({
    required Directory sessionDir,
    required Map<String, dynamic> framewiseSignals,
    required List<Map<String, dynamic>> timeline,
  }) async {
    final List<Map<String, dynamic>> frames = _listMap(
      framewiseSignals['frames'],
    );
    final Map<String, dynamic>? calibratedGazePayload =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.calibratedGazeFrames,
        );

    final List<Map<String, dynamic>> exportedStimuli = [];

    for (final Map<String, dynamic> item in timeline) {
      final String stimulusId = item['stimulus_id']?.toString() ?? '';

      if (stimulusId.trim().isEmpty) {
        continue;
      }

      final double globalStartSec = _number(item['global_start_sec']);

      final double globalEndSec = _number(
        item['global_end_sec'],
        fallback: globalStartSec,
      );

      if (globalEndSec <= globalStartSec) {
        continue;
      }

      final Map<String, dynamic> stimulus = _stimulusFromItem(item);

      final String stimulusType =
          stimulus['type']?.toString() ??
          item['stimulus_type']?.toString() ??
          'video';

      final String paperCategory =
          stimulus['paper_category']?.toString() ??
          item['paper_category']?.toString() ??
          stimulus['category']?.toString() ??
          'unknown';

      final List<Map<String, dynamic>> stimulusFrames = frames.where((
        Map<String, dynamic> frame,
      ) {
        final double elapsedSec = _number(frame['time_ms']) / 1000.0;
        return elapsedSec >= globalStartSec && elapsedSec <= globalEndSec;
      }).toList();

      final List<List<dynamic>> csvRows = _buildRows(
        frames: stimulusFrames,
        stimulusId: stimulusId,
        stimulusType: stimulusType,
        paperCategory: paperCategory,
        calibratedGazePayload: calibratedGazePayload,
      );

      final String csvFileName = SessionFileNames.framewiseLogCsv(stimulusId);

      await SessionService.saveCsv(
        sessionDir: sessionDir,
        fileName: csvFileName,
        headers: csvHeaders,
        rows: csvRows,
      );

      final Map<String, dynamic> summary = _buildSummary(
        stimulusId: stimulusId,
        stimulusType: stimulusType,
        paperCategory: paperCategory,
        globalStartSec: globalStartSec,
        globalEndSec: globalEndSec,
        frames: stimulusFrames,
        csvFileName: csvFileName,
      );

      final String summaryFileName = SessionFileNames.framewiseSummaryJson(
        stimulusId,
      );

      await SessionService.saveJson(
        sessionDir: sessionDir,
        fileName: summaryFileName,
        data: summary,
      );

      exportedStimuli.add({
        'stimulus_id': stimulusId,
        'csv_file': csvFileName,
        'summary_file': summaryFileName,
        'frame_count': stimulusFrames.length,
        'valid_face_frame_count': summary['valid_face_frame_count'],
        'face_presence_ratio': summary['face_presence_ratio'],
      });
    }

    return {
      'schema_version': 'python_mobile_replica_framewise_export_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'source_file': SessionFileNames.framewiseFaceSignals,
      'exported_stimulus_count': exportedStimuli.length,
      'exported_stimuli': exportedStimuli,
    };
  }

  static List<List<dynamic>> _buildRows({
    required List<Map<String, dynamic>> frames,
    required String stimulusId,
    required String stimulusType,
    required String paperCategory,
    required Map<String, dynamic>? calibratedGazePayload,
  }) {
    final List<List<dynamic>> rows = [];
    final Map<int, Map<String, dynamic>> calibratedGazeByFrameIndex =
        _calibratedGazeByFrameIndex(calibratedGazePayload);

    double? previousYaw;
    double? previousPitch;
    double? previousRoll;
    double? previousElapsedTimeSec;
    double? previousAngularVelocity;

    for (final Map<String, dynamic> frame in frames) {
      final bool faceDetected = frame['face_detected'] == true;

      final double elapsedTimeSec = _number(frame['time_ms']) / 1000.0;

      final double? leftEye = _nullableNumber(
        frame['left_eye_open_probability'],
      );

      final double? rightEye = _nullableNumber(
        frame['right_eye_open_probability'],
      );

      final double? avgEye = leftEye == null || rightEye == null
          ? null
          : (leftEye + rightEye) / 2.0;

      final bool eyeOpen = avgEye == null ? false : avgEye >= 0.25;

      final String blinkState = avgEye == null
          ? 'unknown'
          : eyeOpen
          ? 'open'
          : 'closed';

      final Map<String, dynamic>? box = _box(frame['bounding_box']);

      final double? centerX = box == null
          ? null
          : _nullableNumber(box['center_x']);

      final double? centerY = box == null
          ? null
          : _nullableNumber(box['center_y']);

      final double? yaw = _nullableNumber(frame['head_yaw']);
      final double? pitch = _nullableNumber(frame['head_pitch']);
      final double? roll = _nullableNumber(frame['head_roll']);

      double? headMovement;
      double? headAcceleration;

      if (faceDetected && yaw != null && pitch != null && roll != null) {
        if (previousYaw != null &&
            previousPitch != null &&
            previousRoll != null &&
            previousElapsedTimeSec != null) {
          final double dt = elapsedTimeSec - previousElapsedTimeSec;

          if (dt > 0) {
            final double dYaw = yaw - previousYaw;
            final double dPitch = pitch - previousPitch;
            final double dRoll = roll - previousRoll;

            headMovement = sqrt(
              (dYaw * dYaw) + (dPitch * dPitch) + (dRoll * dRoll),
            ) / dt;

            if (previousAngularVelocity != null) {
              headAcceleration =
                  (headMovement - previousAngularVelocity).abs() / dt;
            }

            previousAngularVelocity = headMovement;
          }
        }

        previousYaw = yaw;
        previousPitch = pitch;
        previousRoll = roll;
        previousElapsedTimeSec = elapsedTimeSec;
      }

      final double? smiling = _nullableNumber(frame['smiling_probability']);

      final double? mouthOpenSignal =
          _nullableNumber(frame['mouth_open_signal']) ?? smiling;

      final double? eyebrowSignal = _nullableNumber(frame['eyebrow_signal']);
      final int frameIndex = _intNumber(frame['frame_index']);

      final Map<String, dynamic>? gazeFrame =
          calibratedGazeByFrameIndex[frameIndex];

      final double? calibratedGazeX = _nullableNumber(gazeFrame?['gaze_x']);
      final double? calibratedGazeY = _nullableNumber(gazeFrame?['gaze_y']);

      final bool calibratedGazeValid = gazeFrame?['gaze_valid'] == true;

      rows.add([
        frame['timestamp_ms'],
        _round4(elapsedTimeSec),
        stimulusId,
        stimulusType,
        paperCategory,
        frame['frame_index'],
        faceDetected,
        _roundNullable(leftEye),
        _roundNullable(rightEye),
        _roundNullable(avgEye),
        eyeOpen,
        blinkState,
        _roundNullable(calibratedGazeX),
        _roundNullable(calibratedGazeY),
        calibratedGazeValid,
        calibratedGazeValid ? 'mobile_iris_landmark_calibrated_gaze' : '',
        _roundNullable(yaw),
        _roundNullable(pitch),
        _roundNullable(roll),
        _roundNullable(centerX),
        _roundNullable(centerY),
        _roundNullable(headMovement),
        _roundNullable(headAcceleration),
        _roundNullable(mouthOpenSignal),
        _roundNullable(eyebrowSignal),
      ]);
    }

    return rows;
  }

  static Map<String, dynamic> _buildSummary({
    required String stimulusId,
    required String stimulusType,
    required String paperCategory,
    required double globalStartSec,
    required double globalEndSec,
    required List<Map<String, dynamic>> frames,
    required String csvFileName,
  }) {
    final int totalFrameCount = frames.length;

    final int validFaceFrameCount = frames
        .where((Map<String, dynamic> frame) => frame['face_detected'] == true)
        .length;

    final double facePresenceRatio = totalFrameCount == 0
        ? 0.0
        : validFaceFrameCount / totalFrameCount;

    final List<double> avgEyes = frames
        .map((Map<String, dynamic> frame) {
          final double? left = _nullableNumber(
            frame['left_eye_open_probability'],
          );

          final double? right = _nullableNumber(
            frame['right_eye_open_probability'],
          );

          if (left == null || right == null) {
            return null;
          }

          return (left + right) / 2.0;
        })
        .whereType<double>()
        .toList();

    final int blinkCount = _countBlinks(avgEyes);

    final List<double> yawValues = frames
        .map((Map<String, dynamic> frame) => _nullableNumber(frame['head_yaw']))
        .whereType<double>()
        .toList();

    final List<double> pitchValues = frames
        .map(
          (Map<String, dynamic> frame) => _nullableNumber(frame['head_pitch']),
        )
        .whereType<double>()
        .toList();

    final List<double> rollValues = frames
        .map(
          (Map<String, dynamic> frame) => _nullableNumber(frame['head_roll']),
        )
        .whereType<double>()
        .toList();

    final Map<String, dynamic> headDynamics = _headAngularDynamicsSummary(frames);

    final List<double> mouthOpenValues = frames
        .map(
          (Map<String, dynamic> frame) =>
              _nullableNumber(frame['mouth_open_signal']) ??
              _nullableNumber(frame['smiling_probability']),
        )
        .whereType<double>()
        .toList();

    final List<double> eyebrowSignalValues = frames
        .map(
          (Map<String, dynamic> frame) =>
              _nullableNumber(frame['eyebrow_signal']),
        )
        .whereType<double>()
        .toList();

    return {
      'schema_version': 'python_mobile_replica_framewise_summary_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'stimulus_id': stimulusId,
      'stimulus_type': stimulusType,
      'paper_category': paperCategory,
      'global_start_sec': _round4(globalStartSec),
      'global_end_sec': _round4(globalEndSec),
      'duration_sec': _round4(globalEndSec - globalStartSec),
      'csv_file': csvFileName,
      'total_frame_count': totalFrameCount,
      'valid_face_frame_count': validFaceFrameCount,
      'face_presence_ratio': _round4(facePresenceRatio),
      'blink_count_proxy': blinkCount,
      'mean_eye_open_probability': _round4(_mean(avgEyes)),
      'mean_yaw_proxy': _round4(_mean(yawValues)),
      'mean_pitch_proxy': _round4(_mean(pitchValues)),
      'mean_roll_proxy_deg': _round4(_mean(rollValues)),
      'head_movement_source': 'head_pose_angular_velocity_deg_per_sec',
      'mean_head_angular_velocity_deg_per_sec':
          headDynamics['mean_velocity_deg_per_sec'],
      'head_angular_velocity_complexity_std':
          headDynamics['velocity_complexity_std'],
      'mean_head_angular_acceleration_deg_per_sec2':
          headDynamics['mean_acceleration_deg_per_sec2'],
      'mouth_open_proxy_mean': _round4(_mean(mouthOpenValues)),
      'mouth_complexity_proxy': _round4(_std(mouthOpenValues)),
      'eyebrow_signal_mean': eyebrowSignalValues.isEmpty
          ? null
          : _round4(_mean(eyebrowSignalValues)),
      'eyebrow_complexity_proxy': eyebrowSignalValues.length <= 1
          ? null
          : _round4(_std(eyebrowSignalValues)),
      'measurement_source': 'mobile_native_mlkit_mediapipe_head_pose_contour_to_python_csv',
    };
  }

  static Map<String, dynamic> _headAngularDynamicsSummary(
    List<Map<String, dynamic>> frames,
  ) {
    final List<double> velocities = [];
    final List<double> accelerations = [];

    double? previousYaw;
    double? previousPitch;
    double? previousRoll;
    double? previousTimeSec;
    double? previousVelocity;

    for (final Map<String, dynamic> frame in frames) {
      if (frame['face_detected'] != true) {
        continue;
      }

      final double? yaw = _nullableNumber(frame['head_yaw']);
      final double? pitch = _nullableNumber(frame['head_pitch']);
      final double? roll = _nullableNumber(frame['head_roll']);
      final double timeSec = _number(frame['time_ms']) / 1000.0;

      if (yaw == null || pitch == null || roll == null) {
        continue;
      }

      if (previousYaw != null &&
          previousPitch != null &&
          previousRoll != null &&
          previousTimeSec != null) {
        final double dt = timeSec - previousTimeSec;

        if (dt > 0) {
          final double dYaw = yaw - previousYaw;
          final double dPitch = pitch - previousPitch;
          final double dRoll = roll - previousRoll;

          final double velocity = sqrt(
            (dYaw * dYaw) + (dPitch * dPitch) + (dRoll * dRoll),
          ) / dt;

          velocities.add(velocity);

          if (previousVelocity != null) {
            accelerations.add((velocity - previousVelocity).abs() / dt);
          }

          previousVelocity = velocity;
        }
      }

      previousYaw = yaw;
      previousPitch = pitch;
      previousRoll = roll;
      previousTimeSec = timeSec;
    }

    return {
      'mean_velocity_deg_per_sec': velocities.isEmpty
          ? null
          : _round4(_mean(velocities)),
      'velocity_complexity_std': velocities.length <= 1
          ? null
          : _round4(_std(velocities)),
      'mean_acceleration_deg_per_sec2': accelerations.isEmpty
          ? null
          : _round4(_mean(accelerations)),
      'valid_velocity_sample_count': velocities.length,
      'valid_acceleration_sample_count': accelerations.length,
    };
  }

  static int _countBlinks(List<double> avgEyes) {
    int count = 0;
    bool wasClosed = false;

    for (final double eye in avgEyes) {
      final bool closed = eye < 0.25;

      if (closed && !wasClosed) {
        count += 1;
        wasClosed = true;
      }

      if (!closed) {
        wasClosed = false;
      }
    }

    return count;
  }

  static Map<String, dynamic> _stimulusFromItem(Map<String, dynamic> item) {
    final dynamic stimulus = item['stimulus'];

    if (stimulus is Map) {
      return Map<String, dynamic>.from(stimulus);
    }

    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _listMap(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Map<String, dynamic>? _box(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  static double _number(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static double? _nullableNumber(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce((double a, double b) => a + b) / values.length;
  }

  static double _std(List<double> values) {
    if (values.length <= 1) {
      return 0.0;
    }

    final double average = _mean(values);

    final double variance =
        values
            .map((double value) {
              final double diff = value - average;
              return diff * diff;
            })
            .reduce((double a, double b) => a + b) /
        values.length;

    return sqrt(variance);
  }

  static double _round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }

  static double? _roundNullable(double? value) {
    if (value == null) {
      return null;
    }

    return _round4(value);
  }

  static Map<int, Map<String, dynamic>> _calibratedGazeByFrameIndex(
    Map<String, dynamic>? payload,
  ) {
    final Map<int, Map<String, dynamic>> result = {};

    if (payload == null || payload['frames'] is! List) {
      return result;
    }

    final List<dynamic> frames = payload['frames'] as List<dynamic>;

    for (final dynamic rawFrame in frames) {
      if (rawFrame is! Map) continue;

      final Map<String, dynamic> frame = Map<String, dynamic>.from(rawFrame);

      final int frameIndex = _intNumber(frame['frame_index']);

      result[frameIndex] = frame;
    }

    return result;
  }

  static int _intNumber(dynamic value) {
    if (value is int) return value;

    if (value is num) return value.toInt();

    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }
}
