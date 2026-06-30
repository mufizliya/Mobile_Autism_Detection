import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../native/native_iris_recorder_service.dart';
import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../video_protocol/video_protocol_screen.dart';

class GazeCalibrationScreen extends StatefulWidget {
  const GazeCalibrationScreen({
    super.key,
    required this.sessionDir,
    required this.childInfo,
  });

  final Directory sessionDir;
  final Map<String, dynamic> childInfo;

  @override
  State<GazeCalibrationScreen> createState() => _GazeCalibrationScreenState();
}

class _GazeCalibrationScreenState extends State<GazeCalibrationScreen> {
  static const int dotDurationMs = 2500;
  static const int introDurationMs = 1500;

  final Stopwatch stopwatch = Stopwatch();

  Timer? timer;

  bool isRunning = false;
  bool isFinished = false;
  bool isSaving = false;

  String status = 'Calibration not started yet.';

  int currentTargetIndex = -1;

  final List<Map<String, dynamic>> targets = const [
    {'id': 'top_left', 'target_x': 0.15, 'target_y': 0.15},
    {'id': 'top_center', 'target_x': 0.50, 'target_y': 0.15},
    {'id': 'top_right', 'target_x': 0.85, 'target_y': 0.15},
    {'id': 'middle_left', 'target_x': 0.15, 'target_y': 0.50},
    {'id': 'center', 'target_x': 0.50, 'target_y': 0.50},
    {'id': 'middle_right', 'target_x': 0.85, 'target_y': 0.50},
    {'id': 'bottom_left', 'target_x': 0.15, 'target_y': 0.85},
    {'id': 'bottom_center', 'target_x': 0.50, 'target_y': 0.85},
    {'id': 'bottom_right', 'target_x': 0.85, 'target_y': 0.85},
  ];
  @override
  void initState() {
    super.initState();
    enterLandscapeFullscreen();
  }

  Future<void> enterLandscapeFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> startCalibration() async {
    setState(() {
      isRunning = true;
      isFinished = false;
      isSaving = false;
      currentTargetIndex = -1;
      status = 'Starting iris recorder...';
    });

    stopwatch
      ..reset()
      ..start();

    try {
      await NativeIrisRecorderService.start();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isRunning = false;
        status = 'Failed to start iris recorder: $error';
      });

      return;
    }

    timer?.cancel();

    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      updateTarget();
    });

    if (!mounted) return;

    setState(() {
      status = 'Look at each dot as it appears.';
    });
  }

  Future<void> updateTarget() async {
    final int elapsedMs = stopwatch.elapsedMilliseconds;

    if (elapsedMs < introDurationMs) {
      if (currentTargetIndex != -1 && mounted) {
        setState(() {
          currentTargetIndex = -1;
        });
      }

      return;
    }

    final int targetElapsedMs = elapsedMs - introDurationMs;
    final int index = targetElapsedMs ~/ dotDurationMs;

    if (index >= targets.length) {
      await finishCalibration();
      return;
    }

    if (index != currentTargetIndex && mounted) {
      setState(() {
        currentTargetIndex = index;
      });
    }
  }

  Future<void> finishCalibration() async {
    if (!isRunning || isSaving) {
      return;
    }

    timer?.cancel();
    stopwatch.stop();

    setState(() {
      isRunning = false;
      isSaving = true;
      status = 'Saving gaze calibration...';
    });

    Map<String, dynamic> rawPayload;

    try {
      rawPayload = await NativeIrisRecorderService.stopAndSave(
        sessionDir: widget.sessionDir,
        fileName: SessionFileNames.gazeCalibrationRawIris,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
        status = 'Failed to stop/save iris recorder: $error';
      });

      return;
    }

    final Map<String, dynamic> calibration = buildCalibration(
      rawPayload: rawPayload,
    );

    final Map<String, dynamic> quality = buildCalibrationQuality(
      calibration: calibration,
      rawPayload: rawPayload,
    );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.gazeCalibration,
      data: calibration,
    );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.gazeCalibrationQuality,
      data: quality,
    );

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'updated_at': DateTime.now().toIso8601String(),
        'completed_modules': ['child_info', 'scq', 'gaze_calibration'],
        'files': {
          SessionFileNames.childInfo: true,
          SessionFileNames.scqResults: true,
          SessionFileNames.gazeCalibrationRawIris: true,
          SessionFileNames.gazeCalibration: true,
          SessionFileNames.gazeCalibrationQuality: true,
        },
        'gaze_calibration_quality': quality,
      },
    );

    if (!mounted) return;

    setState(() {
      isFinished = true;
      isSaving = false;
      currentTargetIndex = -1;
      status =
          'Calibration saved.\n'
          'Valid targets: ${quality['valid_target_count']} / ${targets.length}\n'
          'Overall status: ${quality['overall_status']}';
    });
  }

  Map<String, dynamic> buildCalibration({
    required Map<String, dynamic> rawPayload,
  }) {
    final List<Map<String, dynamic>> frames = listMap(rawPayload['frames']);

    final List<Map<String, dynamic>> calibrationPoints = [];

    for (int i = 0; i < targets.length; i++) {
      final Map<String, dynamic> target = targets[i];

      final int startMs = introDurationMs + i * dotDurationMs;
      final int endMs = startMs + dotDurationMs;

      final List<Map<String, dynamic>> targetFrames = frames.where((
        Map<String, dynamic> frame,
      ) {
        final double timeMs = number(frame['time_ms']);
        return timeMs >= startMs && timeMs < endMs;
      }).toList();

      final List<Map<String, dynamic>> validFrames = targetFrames.where((
        Map<String, dynamic> frame,
      ) {
        final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);
        return frame['face_detected'] == true &&
            iris != null &&
            iris['has_iris_landmarks'] == true;
      }).toList();

      final List<double> averageIrisXValues = validFrames
          .map((Map<String, dynamic> frame) {
            final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

            return nullableNumber(iris?['average_iris_in_eye_x']);
          })
          .whereType<double>()
          .toList();

      final List<double> leftIrisXValues = validFrames
          .map((Map<String, dynamic> frame) {
            final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

            return nullableNumber(iris?['left_iris_in_eye_x']);
          })
          .whereType<double>()
          .toList();

      final List<double> rightIrisXValues = validFrames
          .map((Map<String, dynamic> frame) {
            final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

            return nullableNumber(iris?['right_iris_in_eye_x']);
          })
          .whereType<double>()
          .toList();

      final List<double> irisCenterXValues = validFrames
          .map((Map<String, dynamic> frame) {
            final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

            final double? leftX = nullableNumber(iris?['left_iris_center_x']);

            final double? rightX = nullableNumber(iris?['right_iris_center_x']);

            if (leftX == null || rightX == null) {
              return null;
            }

            return (leftX + rightX) / 2.0;
          })
          .whereType<double>()
          .toList();

      final List<double> irisCenterYValues = validFrames
          .map((Map<String, dynamic> frame) {
            final Map<String, dynamic>? iris = mapOrNull(frame['iris_signals']);

            final double? leftY = nullableNumber(iris?['left_iris_center_y']);

            final double? rightY = nullableNumber(iris?['right_iris_center_y']);

            if (leftY == null || rightY == null) {
              return null;
            }

            return (leftY + rightY) / 2.0;
          })
          .whereType<double>()
          .toList();

      calibrationPoints.add({
        'target_id': target['id'],
        'target_x': target['target_x'],
        'target_y': target['target_y'],
        'start_ms': startMs,
        'end_ms': endMs,
        'total_frame_count': targetFrames.length,
        'valid_iris_frame_count': validFrames.length,
        'mean_average_iris_in_eye_x': averageIrisXValues.isEmpty
            ? null
            : round4(mean(averageIrisXValues)),
        'mean_left_iris_in_eye_x': leftIrisXValues.isEmpty
            ? null
            : round4(mean(leftIrisXValues)),
        'mean_right_iris_in_eye_x': rightIrisXValues.isEmpty
            ? null
            : round4(mean(rightIrisXValues)),
        'mean_iris_center_x': irisCenterXValues.isEmpty
            ? null
            : round4(mean(irisCenterXValues)),
        'mean_iris_center_y': irisCenterYValues.isEmpty
            ? null
            : round4(mean(irisCenterYValues)),
      });
    }

    final List<Map<String, dynamic>> validPoints = calibrationPoints.where((
      Map<String, dynamic> point,
    ) {
      return point['mean_average_iris_in_eye_x'] != null &&
          point['mean_iris_center_y'] != null;
    }).toList();

    final Map<String, dynamic> xFitIrisInEye = fitLinear(
      points: validPoints,
      inputKey: 'mean_average_iris_in_eye_x',
      targetKey: 'target_x',
    );

    final Map<String, dynamic> xFitIrisCenter = fitLinear(
      points: validPoints,
      inputKey: 'mean_iris_center_x',
      targetKey: 'target_x',
    );

    final Map<String, dynamic> xFit =
        number(xFitIrisCenter['rmse']) < number(xFitIrisInEye['rmse'])
        ? xFitIrisCenter
        : xFitIrisInEye;

    final String xInput =
        number(xFitIrisCenter['rmse']) < number(xFitIrisInEye['rmse'])
        ? 'mean_iris_center_x'
        : 'mean_average_iris_in_eye_x';

    final Map<String, dynamic> yFit = fitLinear(
      points: validPoints,
      inputKey: 'mean_iris_center_y',
      targetKey: 'target_y',
    );

    return {
      'schema_version': 'mobile_iris_gaze_calibration_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'method':
          'nine_point_screen_dot_calibration_with_mediapipe_iris_landmarks',
      'target_count': targets.length,
      'valid_target_count': validPoints.length,
      'dot_duration_ms': dotDurationMs,
      'intro_duration_ms': introDurationMs,
      'raw_iris_file': SessionFileNames.gazeCalibrationRawIris,
      'calibration_points': calibrationPoints,
      'mapping': {
        'gaze_x': {
          'input': xInput,
          'candidate_models': {
            'mean_average_iris_in_eye_x': xFitIrisInEye,
            'mean_iris_center_x': xFitIrisCenter,
          },
          ...xFit,
        },
        'gaze_y': {'input': 'mean_iris_center_y', ...yFit},
      },
      'usage_note':
          'This maps MediaPipe iris landmark signals to normalized screen gaze coordinates. It is calibration-based, not clinical eye-tracking hardware.',
    };
  }

  Map<String, dynamic> buildCalibrationQuality({
    required Map<String, dynamic> calibration,
    required Map<String, dynamic> rawPayload,
  }) {
    final Map<String, dynamic> summary = rawPayload['summary'] is Map
        ? Map<String, dynamic>.from(rawPayload['summary'] as Map)
        : <String, dynamic>{};

    final int validTargetCount = intNumber(calibration['valid_target_count']);

    final double facePresenceRatio = number(summary['face_presence_ratio']);

    final double irisPresenceRatio = number(summary['iris_presence_ratio']);

    final Map<String, dynamic> mapping = calibration['mapping'] is Map
        ? Map<String, dynamic>.from(calibration['mapping'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> gazeX = mapping['gaze_x'] is Map
        ? Map<String, dynamic>.from(mapping['gaze_x'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> gazeY = mapping['gaze_y'] is Map
        ? Map<String, dynamic>.from(mapping['gaze_y'] as Map)
        : <String, dynamic>{};

    final double xRmse = number(gazeX['rmse']);
    final double yRmse = number(gazeY['rmse']);

    String overallStatus = 'valid';

    if (validTargetCount < 6 ||
        facePresenceRatio < 0.75 ||
        irisPresenceRatio < 0.75) {
      overallStatus = 'failed';
    } else if (xRmse > 0.25 || yRmse > 0.25) {
      overallStatus = 'warning';
    }

    return {
      'schema_version': 'mobile_iris_gaze_calibration_quality_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'overall_status': overallStatus,
      'valid_target_count': validTargetCount,
      'expected_target_count': targets.length,
      'face_presence_ratio': round4(facePresenceRatio),
      'iris_presence_ratio': round4(irisPresenceRatio),
      'x_mapping_rmse': round4(xRmse),
      'y_mapping_rmse': round4(yRmse),
      'quality_rule': {
        'valid':
            'At least 6 valid targets, face/iris presence >= 0.75, and x/y RMSE <= 0.25.',
        'warning':
            'Enough targets and iris data, but calibration error is high.',
        'failed': 'Not enough valid targets or poor face/iris visibility.',
      },
    };
  }

  Map<String, dynamic> fitLinear({
    required List<Map<String, dynamic>> points,
    required String inputKey,
    required String targetKey,
  }) {
    final List<double> xs = [];
    final List<double> ys = [];

    for (final Map<String, dynamic> point in points) {
      final double? x = nullableNumber(point[inputKey]);
      final double? y = nullableNumber(point[targetKey]);

      if (x == null || y == null) {
        continue;
      }

      xs.add(x);
      ys.add(y);
    }

    if (xs.length < 2) {
      return {
        'intercept': null,
        'slope': null,
        'rmse': 1.0,
        'sample_count': xs.length,
      };
    }

    final double meanX = mean(xs);
    final double meanY = mean(ys);

    double numerator = 0.0;
    double denominator = 0.0;

    for (int i = 0; i < xs.length; i++) {
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
      denominator += pow(xs[i] - meanX, 2).toDouble();
    }

    final double slope = denominator == 0 ? 0.0 : numerator / denominator;
    final double intercept = meanY - slope * meanX;

    final List<double> errors = [];

    for (int i = 0; i < xs.length; i++) {
      final double predicted = intercept + slope * xs[i];
      errors.add(predicted - ys[i]);
    }

    return {
      'intercept': round4(intercept),
      'slope': round4(slope),
      'rmse': round4(rmse(errors)),
      'sample_count': xs.length,
    };
  }

  List<Map<String, dynamic>> listMap(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic>? mapOrNull(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  double? nullableNumber(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  double number(dynamic value) {
    return nullableNumber(value) ?? 0.0;
  }

  int intNumber(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  double mean(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce((double a, double b) => a + b) / values.length;
  }

  double rmse(List<double> errors) {
    if (errors.isEmpty) {
      return 1.0;
    }

    final double mse =
        errors
            .map((double error) => error * error)
            .reduce((double a, double b) => a + b) /
        errors.length;

    return sqrt(mse);
  }

  double round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }

  void goToVideoProtocol() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return VideoProtocolScreen(
            sessionDir: widget.sessionDir,
            childInfo: widget.childInfo,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? currentTarget =
        currentTargetIndex >= 0 && currentTargetIndex < targets.length
        ? targets[currentTargetIndex]
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Look and Follow')),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: [
                Positioned.fill(child: Container(color: Colors.white)),

                if (currentTarget == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Look and Follow',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Look at each dot until it moves.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 24),
                          if (!isRunning && !isFinished)
                            ElevatedButton(
                              onPressed: startCalibration,
                              child: const Text('Start'),
                            ),
                          if (isFinished)
                            ElevatedButton(
                              onPressed: goToVideoProtocol,
                              child: const Text('Continue'),
                            ),
                          const SizedBox(height: 20),
                          if (!isFinished)
                            Text(
                              isRunning ? 'Follow the dot' : 'Ready',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                if (currentTarget != null)
                  Positioned(
                    left:
                        constraints.maxWidth *
                            number(currentTarget['target_x']) -
                        22,
                    top:
                        constraints.maxHeight *
                            number(currentTarget['target_y']) -
                        22,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 4),
                      ),
                    ),
                  ),

                if (isSaving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
