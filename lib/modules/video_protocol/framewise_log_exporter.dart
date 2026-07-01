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

      final double? leftMlkitEye = _nullableNumber(
        frame['left_eye_open_probability'],
      );

      final double? rightMlkitEye = _nullableNumber(
        frame['right_eye_open_probability'],
      );

      final double? leftMediaPipeEar = _nullableNumber(
        frame['left_mediapipe_ear'],
      );

      final double? rightMediaPipeEar = _nullableNumber(
        frame['right_mediapipe_ear'],
      );

      final double? avgMediaPipeEar = _nullableNumber(
        frame['average_mediapipe_ear'],
      );

      final double? avgMlkitEye = leftMlkitEye == null || rightMlkitEye == null
          ? null
          : (leftMlkitEye + rightMlkitEye) / 2.0;

      final double? blinkSignal = avgMediaPipeEar ?? avgMlkitEye;
      final bool usingMediaPipeEar = avgMediaPipeEar != null;

      final bool eyeOpen = blinkSignal == null
          ? false
          : usingMediaPipeEar
              ? blinkSignal >= 0.23
              : blinkSignal >= 0.65;

      final String blinkState = blinkSignal == null
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

            headMovement =
                sqrt((dYaw * dYaw) + (dPitch * dPitch) + (dRoll * dRoll)) / dt;

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
        _roundNullable(leftMediaPipeEar ?? leftMlkitEye),
        _roundNullable(rightMediaPipeEar ?? rightMlkitEye),
        _roundNullable(blinkSignal),
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

    final List<double> mediaPipeEarValues = frames
        .map(
          (Map<String, dynamic> frame) =>
              _nullableNumber(frame['average_mediapipe_ear']),
        )
        .whereType<double>()
        .toList();

    final Map<String, dynamic> blinkEvents = _detectBlinkEvents(frames);

    final int blinkCountProxy = _countBlinks(avgEyes);
    final int blinkCountEvent = _intNumber(blinkEvents['blink_count']);
    final double durationSecForBlink = max(0.0, globalEndSec - globalStartSec);
    final double? blinkRatePerMinEvent = durationSecForBlink <= 0
        ? null
        : blinkCountEvent / durationSecForBlink * 60.0;

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

    final Map<String, dynamic> headDynamics = _headAngularDynamicsSummary(
      frames,
    );

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

    final Map<String, dynamic> mouthComplexity = _signalComplexitySummary(
      mouthOpenValues,
      signalName: 'mouth_open_signal',
    );

    final Map<String, dynamic> eyebrowComplexity = _signalComplexitySummary(
      eyebrowSignalValues,
      signalName: 'eyebrow_signal',
    );

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
      'blink_count_proxy': blinkCountProxy,
      'blink_count_event': blinkCountEvent,
      'blink_rate_per_min_event': blinkRatePerMinEvent == null
          ? null
          : _round4(blinkRatePerMinEvent),
      'blink_event_detection': blinkEvents,
      'blink_signal_source': blinkEvents['signal_source'],
      'blink_estimated_sampling_fps': blinkEvents['estimated_sampling_fps'],
      'mean_mediapipe_eye_aspect_ratio': mediaPipeEarValues.isEmpty
          ? null
          : _round4(_mean(mediaPipeEarValues)),
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
      'mouth_open_proxy_mean': mouthComplexity['mean'],
      'mouth_complexity_proxy': mouthComplexity['std'],
      'mouth_complexity_composite': mouthComplexity['composite_complexity'],
      'mouth_complexity_rmssd': mouthComplexity['rmssd'],
      'mouth_complexity_movement_energy': mouthComplexity['movement_energy'],
      'mouth_complexity_range': mouthComplexity['range'],
      'mouth_complexity_valid_sample_count':
          mouthComplexity['valid_sample_count'],
      'mouth_complexity_signal_quality': mouthComplexity['quality'],
      'mouth_complexity_details': mouthComplexity,
      'eyebrow_signal_mean': eyebrowComplexity['mean'],
      'eyebrow_complexity_proxy': eyebrowComplexity['std'],
      'eyebrow_complexity_composite': eyebrowComplexity['composite_complexity'],
      'eyebrow_complexity_rmssd': eyebrowComplexity['rmssd'],
      'eyebrow_complexity_movement_energy': eyebrowComplexity['movement_energy'],
      'eyebrow_complexity_range': eyebrowComplexity['range'],
      'eyebrow_complexity_valid_sample_count':
          eyebrowComplexity['valid_sample_count'],
      'eyebrow_complexity_signal_quality': eyebrowComplexity['quality'],
      'eyebrow_complexity_details': eyebrowComplexity,
      'measurement_source':
          'mobile_native_mlkit_mediapipe_head_pose_contour_to_python_csv',
    };
  }


  static Map<String, dynamic> _signalComplexitySummary(
    List<double> rawValues, {
    required String signalName,
  }) {
    final List<double> values = rawValues
        .where((double value) => value.isFinite)
        .toList();

    if (values.isEmpty) {
      return {
        'signal_name': signalName,
        'quality': 'missing',
        'valid_sample_count': 0,
        'mean': null,
        'std': null,
        'rmssd': null,
        'movement_energy': null,
        'range': null,
        'composite_complexity': null,
        'method':
            'moving_average_smooth_then_std_rmssd_energy_composite',
      };
    }

    final List<double> smoothed = _movingAverage(values, windowRadius: 1);
    final double meanValue = _mean(smoothed);
    final double stdValue = _std(smoothed);
    final double rmssdValue = _rmssd(smoothed);
    final double movementEnergy = _meanAbsDiff(smoothed);
    final double rangeValue = _range(smoothed);

    final double composite = (stdValue + rmssdValue + movementEnergy) / 3.0;

    String quality = 'valid';

    if (values.length < 5) {
      quality = 'too_few_samples';
    } else if (stdValue < 0.0005 && rmssdValue < 0.0005) {
      quality = 'nearly_constant_signal';
    }

    return {
      'signal_name': signalName,
      'quality': quality,
      'valid_sample_count': values.length,
      'mean': _round4(meanValue),
      'std': _round4(stdValue),
      'rmssd': _round4(rmssdValue),
      'movement_energy': _round4(movementEnergy),
      'range': _round4(rangeValue),
      'composite_complexity': _round4(composite),
      'method':
          'moving_average_smooth_then_std_rmssd_energy_composite',
      'formula_note':
          'Composite is the mean of smoothed signal std, RMSSD, and mean absolute frame-to-frame movement energy.',
    };
  }

  static List<double> _movingAverage(
    List<double> values, {
    required int windowRadius,
  }) {
    if (values.length <= 2 || windowRadius <= 0) {
      return [...values];
    }

    final List<double> smoothed = [];

    for (int i = 0; i < values.length; i++) {
      final int start = max(0, i - windowRadius);
      final int end = min(values.length - 1, i + windowRadius);
      final List<double> window = values.sublist(start, end + 1);
      smoothed.add(_mean(window));
    }

    return smoothed;
  }

  static double _rmssd(List<double> values) {
    if (values.length <= 1) {
      return 0.0;
    }

    final List<double> squaredDiffs = [];

    for (int i = 1; i < values.length; i++) {
      final double diff = values[i] - values[i - 1];
      squaredDiffs.add(diff * diff);
    }

    return sqrt(_mean(squaredDiffs));
  }

  static double _meanAbsDiff(List<double> values) {
    if (values.length <= 1) {
      return 0.0;
    }

    final List<double> diffs = [];

    for (int i = 1; i < values.length; i++) {
      diffs.add((values[i] - values[i - 1]).abs());
    }

    return _mean(diffs);
  }

  static double _range(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce(max) - values.reduce(min);
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

          final double velocity =
              sqrt((dYaw * dYaw) + (dPitch * dPitch) + (dRoll * dRoll)) / dt;

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

  static _BlinkSample? _blinkSampleFromFrame(Map<String, dynamic> frame) {
    final double? averageMediaPipeEar = _nullableNumber(
      frame['average_mediapipe_ear'],
    );

    if (averageMediaPipeEar != null) {
      return _BlinkSample(
        value: averageMediaPipeEar,
        source: 'mediapipe_ear',
      );
    }

    final double? left = _nullableNumber(frame['left_eye_open_probability']);
    final double? right = _nullableNumber(frame['right_eye_open_probability']);

    if (left == null || right == null) {
      return null;
    }

    return _BlinkSample(
      value: (left + right) / 2.0,
      source: 'mlkit_eye_open_probability',
    );
  }

  static Map<String, dynamic> _detectBlinkEvents(
    List<Map<String, dynamic>> frames,
  ) {
    final List<_TimedBlinkSample> mediaPipeSamples = [];
    final List<_TimedBlinkSample> mlkitSamples = [];
    final List<double> allSampleIntervalsSec = [];

    double? previousValidTimeSec;

    for (final Map<String, dynamic> frame in frames) {
      final double timeSec = _number(frame['time_ms']) / 1000.0;
      final _BlinkSample? sample = _blinkSampleFromFrame(frame);

      if (sample == null) {
        continue;
      }

      if (previousValidTimeSec != null) {
        final double interval = timeSec - previousValidTimeSec;
        if (interval > 0) {
          allSampleIntervalsSec.add(interval);
        }
      }

      previousValidTimeSec = timeSec;

      final _TimedBlinkSample timedSample = _TimedBlinkSample(
        timeSec: timeSec,
        value: sample.value,
        source: sample.source,
      );

      if (sample.source == 'mediapipe_ear') {
        mediaPipeSamples.add(timedSample);
      } else {
        mlkitSamples.add(timedSample);
      }
    }

    final bool useMediaPipe = mediaPipeSamples.length >= 5;
    final List<_TimedBlinkSample> samples = useMediaPipe
        ? mediaPipeSamples
        : mlkitSamples;

    if (samples.isEmpty) {
      return {
        'method': 'adaptive_mediapipe_ear_valley_blink_detection',
        'blink_count': 0,
        'valid_eye_sample_count': 0,
        'mediapipe_ear_sample_count': mediaPipeSamples.length,
        'mlkit_eye_probability_sample_count': mlkitSamples.length,
        'signal_source': 'none',
        'estimated_sampling_fps': 0.0,
        'mean_sample_interval_sec': 0.0,
        'events': [],
        'quality_note': 'No usable eye signal samples were available.',
      };
    }

    final List<double> sampleIntervalsSec = [];
    for (int i = 1; i < samples.length; i++) {
      final double interval = samples[i].timeSec - samples[i - 1].timeSec;
      if (interval > 0) {
        sampleIntervalsSec.add(interval);
      }
    }

    final double meanSampleIntervalSec = sampleIntervalsSec.isEmpty
        ? (allSampleIntervalsSec.isEmpty ? 0.0 : _mean(allSampleIntervalsSec))
        : _mean(sampleIntervalsSec);

    final double estimatedSamplingFps = meanSampleIntervalSec <= 0
        ? 0.0
        : 1.0 / meanSampleIntervalSec;

    final List<double> values = samples
        .map((_TimedBlinkSample sample) => sample.value)
        .toList();

    final double medianValue = _percentile(values, 0.50);
    final double p10Value = _percentile(values, 0.10);
    final double p25Value = _percentile(values, 0.25);
    final double p75Value = _percentile(values, 0.75);

    final String signalSource = useMediaPipe
        ? 'mediapipe_ear'
        : 'mlkit_eye_open_probability';

    final double closedThreshold = useMediaPipe
        ? _clampDouble(medianValue * 0.72, 0.16, 0.32)
        : _clampDouble(medianValue * 0.70, 0.25, 0.50);

    final double openThreshold = useMediaPipe
        ? _clampDouble(medianValue * 0.86, closedThreshold + 0.025, 0.42)
        : _clampDouble(medianValue * 0.88, closedThreshold + 0.08, 0.78);

    final double signalSpread = max(0.0, p75Value - p10Value);
    final double minimumDropFromOpen = useMediaPipe
        ? max(0.045, signalSpread * 0.22)
        : max(0.10, signalSpread * 0.30);

    final double valleyCandidateThreshold = useMediaPipe
        ? max(closedThreshold, p25Value)
        : max(closedThreshold, medianValue - minimumDropFromOpen);

    final double minBlinkSeparationSec = estimatedSamplingFps >= 5.0
        ? 0.42
        : 0.65;

    final int recoveryLookAroundSamples = estimatedSamplingFps >= 5.0 ? 3 : 2;
    final double minimumRecovery = useMediaPipe ? 0.025 : 0.08;

    final List<_BlinkCandidate> candidates = [];

    for (int i = 0; i < samples.length; i++) {
      final _TimedBlinkSample current = samples[i];
      final double previousValue = i == 0 ? current.value : samples[i - 1].value;
      final double nextValue = i == samples.length - 1
          ? current.value
          : samples[i + 1].value;

      final bool localMinimum = current.value <= previousValue &&
          current.value <= nextValue;

      final double dropFromOpen = max(0.0, p75Value - current.value);
      final bool lowEnough = current.value <= valleyCandidateThreshold ||
          current.value <= closedThreshold ||
          dropFromOpen >= minimumDropFromOpen;

      if (!localMinimum || !lowEnough || dropFromOpen < minimumDropFromOpen) {
        continue;
      }

      final int beforeStart = max(0, i - recoveryLookAroundSamples);
      final int afterEnd = min(samples.length - 1, i + recoveryLookAroundSamples);

      final double beforeMax = samples
          .sublist(beforeStart, i + 1)
          .map((_TimedBlinkSample sample) => sample.value)
          .reduce(max);

      final double afterMax = samples
          .sublist(i, afterEnd + 1)
          .map((_TimedBlinkSample sample) => sample.value)
          .reduce(max);

      final bool hasRecovery = max(beforeMax, afterMax) - current.value >=
          minimumRecovery;

      if (!hasRecovery) {
        continue;
      }

      candidates.add(
        _BlinkCandidate(
          sampleIndex: i,
          timeSec: current.timeSec,
          lowestSignal: current.value,
          dropFromOpen: dropFromOpen,
          beforeRecoverySignal: beforeMax,
          afterRecoverySignal: afterMax,
        ),
      );
    }

    final List<_BlinkCandidate> selected = [];

    for (final _BlinkCandidate candidate in candidates) {
      if (selected.isEmpty) {
        selected.add(candidate);
        continue;
      }

      final _BlinkCandidate previous = selected.last;
      final double separation = candidate.timeSec - previous.timeSec;

      if (separation < minBlinkSeparationSec) {
        if (candidate.lowestSignal < previous.lowestSignal) {
          selected[selected.length - 1] = candidate;
        }
        continue;
      }

      selected.add(candidate);
    }

    final List<Map<String, dynamic>> events = [];

    for (int i = 0; i < selected.length; i++) {
      final _BlinkCandidate candidate = selected[i];
      final double startTimeSec = candidate.sampleIndex <= 0
          ? candidate.timeSec
          : samples[candidate.sampleIndex - 1].timeSec;
      final double endTimeSec = candidate.sampleIndex >= samples.length - 1
          ? candidate.timeSec
          : samples[candidate.sampleIndex + 1].timeSec;

      events.add({
        'event_index': i + 1,
        'valley_time_sec': _round4(candidate.timeSec),
        'start_time_sec_sampled': _round4(startTimeSec),
        'end_time_sec_sampled': _round4(endTimeSec),
        'duration_sec_sampled': _round4(max(0.0, endTimeSec - startTimeSec)),
        'lowest_blink_signal': _round4(candidate.lowestSignal),
        'open_baseline_signal_p75': _round4(p75Value),
        'drop_from_open_baseline': _round4(candidate.dropFromOpen),
        'before_recovery_signal': _round4(candidate.beforeRecoverySignal),
        'after_recovery_signal': _round4(candidate.afterRecoverySignal),
        'signal_source': signalSource,
        'confidence_note': signalSource == 'mediapipe_ear'
            ? 'Blink event detected as an adaptive local-minimum valley in MediaPipe eyelid EAR.'
            : 'Blink event detected as an adaptive local-minimum valley in ML Kit eye-open probability fallback.',
      });
    }

    return {
      'method': 'adaptive_mediapipe_ear_valley_blink_detection',
      'blink_count': events.length,
      'valid_eye_sample_count': samples.length,
      'mediapipe_ear_sample_count': mediaPipeSamples.length,
      'mlkit_eye_probability_sample_count': mlkitSamples.length,
      'signal_source': signalSource,
      'estimated_sampling_fps': _round4(estimatedSamplingFps),
      'mean_sample_interval_sec': _round4(meanSampleIntervalSec),
      'adaptive_thresholds': {
        'median_signal': _round4(medianValue),
        'p10_signal': _round4(p10Value),
        'p25_signal': _round4(p25Value),
        'p75_open_baseline_signal': _round4(p75Value),
        'closed_threshold': _round4(closedThreshold),
        'open_threshold': _round4(openThreshold),
        'valley_candidate_threshold': _round4(valleyCandidateThreshold),
        'minimum_drop_from_open_baseline': _round4(minimumDropFromOpen),
        'minimum_recovery': _round4(minimumRecovery),
        'minimum_blink_separation_sec': _round4(minBlinkSeparationSec),
        'recovery_lookaround_samples': recoveryLookAroundSamples,
      },
      'candidate_count_before_separation_filter': candidates.length,
      'events': events,
      'quality_note': signalSource == 'mediapipe_ear'
          ? estimatedSamplingFps >= 5.0
              ? 'MediaPipe EAR is available with usable mobile sampling. Blink events are detected as adaptive local-minimum valleys to handle repeated blinks inside low-EAR clusters.'
              : 'MediaPipe EAR is available, but sampling is sparse. Blink count remains a mobile proxy.'
          : 'MediaPipe EAR was unavailable; falling back to adaptive ML Kit eye-open probability proxy.',
    };
  }

  static double _percentile(List<double> values, double p) {
    if (values.isEmpty) {
      return 0.0;
    }

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

  static double _clampDouble(double value, double minValue, double maxValue) {
    return max(minValue, min(maxValue, value));
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

class _TimedBlinkSample {
  const _TimedBlinkSample({
    required this.timeSec,
    required this.value,
    required this.source,
  });

  final double timeSec;
  final double value;
  final String source;
}

class _BlinkSample {
  const _BlinkSample({
    required this.value,
    required this.source,
  });

  final double value;
  final String source;
}

class _BlinkCandidate {
  const _BlinkCandidate({
    required this.sampleIndex,
    required this.timeSec,
    required this.lowestSignal,
    required this.dropFromOpen,
    required this.beforeRecoverySignal,
    required this.afterRecoverySignal,
  });

  final int sampleIndex;
  final double timeSec;
  final double lowestSignal;
  final double dropFromOpen;
  final double beforeRecoverySignal;
  final double afterRecoverySignal;
}
