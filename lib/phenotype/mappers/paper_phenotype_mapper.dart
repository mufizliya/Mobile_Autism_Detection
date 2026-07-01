import 'dart:io';
import 'dart:math';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../models/paper_feature_coverage.dart';
import '../models/paper_feature_names.dart';

class PaperPhenotypeMapper {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final List<FileSystemEntity> entities = await sessionDir.list().toList();

    final List<String> summaryFiles =
        entities
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .where((String name) => name.endsWith('_framewise_summary.json'))
            .toList()
          ..sort();

    final List<String> csvFiles =
        entities
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .where((String name) => name.endsWith('_framewise_log.csv'))
            .toList()
          ..sort();

    final Map<String, Map<String, dynamic>> summariesByStimulus = {};

    for (final String fileName in summaryFiles) {
      final Map<String, dynamic>? summary =
          await SessionService.readJsonIfExists(
            sessionDir: sessionDir,
            fileName: fileName,
          );

      if (summary == null) {
        continue;
      }

      final String stimulusId = summary['stimulus_id']?.toString() ?? '';

      if (stimulusId.isNotEmpty) {
        summariesByStimulus[stimulusId] = summary;
      }
    }

    final Map<String, List<Map<String, String>>> csvRowsByStimulus = {};

    for (final String fileName in csvFiles) {
      final String stimulusId = fileName.replaceAll('_framewise_log.csv', '');

      csvRowsByStimulus[stimulusId] = await _readCsvRows(
        sessionDir: sessionDir,
        fileName: fileName,
      );
    }

    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gameMetrics,
        );

    final Map<String, dynamic>? stimulusEvents =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.stimulusEvents,
        );

    final Map<String, dynamic>? videoTest =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.videoTest,
        );

    final Map<String, Map<String, dynamic>> stimulusById =
        _stimulusByIdFromVideoTest(videoTest);

    final Map<String, dynamic> featureSources = {};
    final Map<String, dynamic> featureNotes = {};
    final Map<String, dynamic> paperFeatures = {};

    void setFeature({
      required String name,
      required dynamic value,
      required String source,
      required String note,
    }) {
      paperFeatures[name] = value;
      featureSources[name] = source;
      featureNotes[name] = note;
    }

    final List<String> socialStimuli = _stimuliByCategory(
      summariesByStimulus,
      'social',
    );

    final List<String> nonsocialStimuli = _stimuliByCategory(
      summariesByStimulus,
      'non_social',
    );

    final List<String> mixedStimuli = _stimuliByCategory(
      summariesByStimulus,
      'mixed',
    );

    final List<String> speechStimuli = _stimuliByCategory(
      summariesByStimulus,
      'speech_social',
    );

    final List<String> allSocialLikeStimuli = [
      ...socialStimuli,
      ...mixedStimuli,
      ...speechStimuli,
    ];

    final List<String> allNonsocialLikeStimuli = [
      ...nonsocialStimuli,
      ...mixedStimuli,
    ];

    setFeature(
      name: PaperFeatureNames.facingForwardSocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        _facingForwardRatio,
      ),
      source: 'mobile_mlkit_head_pose_orientation',
      note:
          'Close mobile proxy for paper feature. Computed as proportion of face-detected frames with modest yaw, pitch, and roll during social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.facingForwardNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        _facingForwardRatio,
      ),
      source: 'mobile_mlkit_head_pose_orientation',
      note:
          'Close mobile proxy for paper feature. Computed as proportion of face-detected frames with modest yaw, pitch, and roll during nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.gazePercentSocial,
      value: _computeGazePercentSocialProxy(
        csvRowsByStimulus: csvRowsByStimulus,
        stimulusById: stimulusById,
        stimulusIds: mixedStimuli,
      ),
      source: 'mobile_unified_recorder_iris_calibrated_gaze_aoi',
      note:
          'Computed using calibrated MediaPipe iris landmarks from the unified native recorder, mapped to normalized screen coordinates, then classified against social/nonsocial AOIs.',
    );

    setFeature(
      name: PaperFeatureNames.gazeSilhouetteScore,
      value: _computeGazeSilhouetteProxy(
        csvRowsByStimulus: csvRowsByStimulus,
        stimulusById: stimulusById,
        stimulusIds: mixedStimuli,
      ),
      source: 'mobile_unified_recorder_iris_calibrated_gaze_aoi',
      note:
          'Computed from calibrated MediaPipe iris landmark gaze coordinates from the unified native recorder and social/nonsocial AOI assignment.',
    );

    setFeature(
      name: PaperFeatureNames.attentionToSpeech,
      value: _meanForStimuli(
        csvRowsByStimulus,
        speechStimuli,
        _facingForwardRatio,
      ),
      source: 'mobile_framewise_csv_proxy',
      note:
          'Proxy only. Uses facing-forward ratio during speech/social stimuli. True paper feature requires gaze to speaking AOI during speech.',
    );

    final Map<String, dynamic> responseToName = _computeResponseToNameProxy(
      stimulusEvents: stimulusEvents,
      csvRowsByStimulus: csvRowsByStimulus,
    );

    setFeature(
      name: PaperFeatureNames.responseToNameDelaySec,
      value: responseToName['mean_delay_sec'],
      source: 'mobile_head_pose_and_calibrated_gaze_response_proxy',
      note:
          'Close mobile proxy. Estimated from actual playback-time name-call cues using post-call head-pose change, head angular velocity, and calibrated gaze shift evidence.'
    );

    setFeature(
      name: PaperFeatureNames.responseToNameProportion,
      value: responseToName['response_proportion'],
      source: 'mobile_head_pose_and_calibrated_gaze_response_proxy',
      note:
          'Close mobile proxy. Proportion of name calls with post-call head-pose or calibrated gaze-shift response evidence.'
    );

    setFeature(
      name: PaperFeatureNames.blinkRateSocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allSocialLikeStimuli,
        'blink_rate_per_min_event',
      ),
      source: 'mobile_eye_open_probability_event_detection',
      note:
          'Close mobile proxy. Blink rate from ML Kit eye-open probability events using closed/open hysteresis thresholds and valid blink-duration filtering during social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.blinkRateNonsocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allNonsocialLikeStimuli,
        'blink_rate_per_min_event',
      ),
      source: 'mobile_eye_open_probability_event_detection',
      note:
          'Close mobile proxy. Blink rate from ML Kit eye-open probability events using closed/open hysteresis thresholds and valid blink-duration filtering during nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementSocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) => _meanColumn(rows, 'head_movement'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement. Uses frame-to-frame yaw/pitch/roll angular velocity in degrees per second.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) => _meanColumn(rows, 'head_movement'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement. Uses frame-to-frame yaw/pitch/roll angular velocity in degrees per second.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementComplexitySocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'head_movement'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement complexity. Uses standard deviation of head-pose angular velocity.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementComplexityNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'head_movement'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement complexity. Uses standard deviation of head-pose angular velocity.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementAccelerationSocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) =>
            _meanColumn(rows, 'head_acceleration'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement acceleration. Uses frame-to-frame change in head-pose angular velocity.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementAccelerationNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) =>
            _meanColumn(rows, 'head_acceleration'),
      ),
      source: 'mobile_mlkit_head_pose_angular_dynamics',
      note:
          'Close mobile proxy for paper head movement acceleration. Uses frame-to-frame change in head-pose angular velocity.',
    );

    setFeature(
      name: PaperFeatureNames.mouthComplexitySocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allSocialLikeStimuli,
        'mouth_complexity_composite',
      ),
      source: 'mobile_mlkit_mouth_contour_complexity_v2',
      note:
          'Close mobile proxy for paper mouth complexity. Uses smoothed normalized mouth-open signal and combines standard deviation, RMSSD, and movement energy across social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.mouthComplexityNonsocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allNonsocialLikeStimuli,
        'mouth_complexity_composite',
      ),
      source: 'mobile_mlkit_mouth_contour_complexity_v2',
      note:
          'Close mobile proxy for paper mouth complexity. Uses smoothed normalized mouth-open signal and combines standard deviation, RMSSD, and movement energy across nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.eyebrowComplexitySocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allSocialLikeStimuli,
        'eyebrow_complexity_composite',
      ),
      source: 'mobile_mlkit_eyebrow_contour_complexity_v2',
      note:
          'Close mobile proxy for paper eyebrow complexity. Uses smoothed normalized eyebrow signal and combines standard deviation, RMSSD, and movement energy across social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.eyebrowComplexityNonsocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allNonsocialLikeStimuli,
        'eyebrow_complexity_composite',
      ),
      source: 'mobile_mlkit_eyebrow_contour_complexity_v2',
      note:
          'Close mobile proxy for paper eyebrow complexity. Uses smoothed normalized eyebrow signal and combines standard deviation, RMSSD, and movement energy across nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.popTheBubblesPoppingRate,
      value: _valueFromNested(gameMetrics, [
        'touch_features',
        'touch_popping_rate',
      ]),
      source: 'flutter_bubble_game_touch_metrics',
      note:
          'Paper-aligned touch feature from bubble game. Current implementation uses touchscreen hit rate per second.',
    );

    setFeature(
      name: PaperFeatureNames.popTheBubblesAccuracyStd,
      value: _valueFromNested(gameMetrics, [
        'touch_features',
        'touch_error_std',
      ]),
      source: 'flutter_bubble_game_touch_metrics',
      note:
          'Paper-aligned touch feature. Current implementation uses standard deviation of touch-to-bubble distance.',
    );

    final bool touchForceAvailable =
        _valueFromNested(gameMetrics, [
          'touch_features',
          'touch_force_available',
        ]) ==
        true;

    setFeature(
      name: PaperFeatureNames.popTheBubblesAverageAppliedForce,
      value: touchForceAvailable
          ? _valueFromNested(gameMetrics, [
              'touch_features',
              'touch_average_applied_force',
            ])
          : null,
      source: touchForceAvailable
          ? 'flutter_pointer_pressure_proxy'
          : 'missing_touch_force',
      note: touchForceAvailable
          ? 'Paper-aligned touch force proxy. Computed from Flutter PointerEvent.pressure values. This is device-dependent and should be calibrated.'
          : 'Paper feature requires touch pressure/applied force. This device/session did not provide usable pressure values, so this is intentionally null.',
    );

    setFeature(
      name: PaperFeatureNames.popTheBubblesAverageTouchLength,
      value: _valueFromNested(gameMetrics, [
        'touch_features',
        'touch_average_length',
      ]),
      source: 'flutter_bubble_game_touch_metrics',
      note:
          'Paper-aligned touch path feature. Taps usually produce near-zero path length; drags produce larger values.',
    );

    final Map<String, dynamic> coverage = PaperFeatureCoverage.build(
      paperFeatures: paperFeatures,
    );

    final Map<String, dynamic> phenotypeVector = {
      'schema_version': 'python_mobile_replica_phenotype_vector_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'important_warning':
          'These are paper-aligned digital phenotype fields, not a diagnostic prediction. Values marked proxy are approximations from current mobile signals.',
      'feature_count': PaperFeatureNames.all.length,
      'features': paperFeatures,
      'feature_sources': featureSources,
      'feature_notes': featureNotes,
      'coverage': coverage,
      'tuning_backlog': _tuningBacklog(),
    };

    final Map<String, dynamic> paperAlignedFeatures = {
      'schema_version': 'sense_to_know_paper_aligned_23_features_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'paper_feature_count': PaperFeatureNames.all.length,
      'paper_feature_names_exact': PaperFeatureNames.all,
      'values': paperFeatures,
      'sources': featureSources,
      'notes': featureNotes,
      'missing_or_proxy_policy':
          'Feature names are kept aligned to the paper. Missing values are not fabricated. Proxy values are explicitly labeled.',
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.phenotypeVector,
      data: phenotypeVector,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.paperAlignedFeatures,
      data: paperAlignedFeatures,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.responseToNameFeatures,
      data: responseToName,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.paperFeatureCoverage,
      data: coverage,
    );

    return {
      'phenotype_vector': phenotypeVector,
      'paper_aligned_features': paperAlignedFeatures,
      'paper_feature_coverage': coverage,
    };
  }

  static List<String> _stimuliByCategory(
    Map<String, Map<String, dynamic>> summariesByStimulus,
    String category,
  ) {
    return summariesByStimulus.entries
        .where((MapEntry<String, Map<String, dynamic>> entry) {
          return entry.value['paper_category'] == category;
        })
        .map((MapEntry<String, Map<String, dynamic>> entry) => entry.key)
        .toList();
  }

  static Future<List<Map<String, String>>> _readCsvRows({
    required Directory sessionDir,
    required String fileName,
  }) async {
    final File file = SessionService.fileInSession(
      sessionDir: sessionDir,
      fileName: fileName,
    );

    if (!await file.exists()) {
      return [];
    }

    final List<String> lines = await file.readAsLines();

    if (lines.length <= 1) {
      return [];
    }

    final List<String> headers = _splitCsvLine(lines.first);

    final List<Map<String, String>> rows = [];

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();

      if (line.isEmpty) {
        continue;
      }

      final List<String> cells = _splitCsvLine(line);

      final Map<String, String> row = {};

      for (int j = 0; j < headers.length; j++) {
        row[headers[j]] = j < cells.length ? cells[j] : '';
      }

      rows.add(row);
    }

    return rows;
  }

  static List<String> _splitCsvLine(String line) {
    final List<String> cells = [];
    final StringBuffer current = StringBuffer();

    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final String char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }

      if (char == ',' && !inQuotes) {
        cells.add(current.toString());
        current.clear();
        continue;
      }

      current.write(char);
    }

    cells.add(current.toString());

    return cells;
  }

  static double? _meanForStimuli(
    Map<String, List<Map<String, String>>> rowsByStimulus,
    List<String> stimulusIds,
    double? Function(List<Map<String, String>> rows) calculator,
  ) {
    final List<double> values = [];

    for (final String stimulusId in stimulusIds) {
      final List<Map<String, String>> rows = rowsByStimulus[stimulusId] ?? [];

      final double? value = calculator(rows);

      if (value != null && value.isFinite) {
        values.add(value);
      }
    }

    if (values.isEmpty) {
      return null;
    }

    return _round4(_mean(values));
  }

  static double? _meanSummaryValueByStimuli(
    Map<String, Map<String, dynamic>> summariesByStimulus,
    List<String> stimulusIds,
    String key,
  ) {
    final List<double> values = [];

    for (final String stimulusId in stimulusIds) {
      final Map<String, dynamic>? summary = summariesByStimulus[stimulusId];

      if (summary == null) {
        continue;
      }

      if (key == 'blink_rate_per_min_proxy') {
        final double blinkCount = _toDouble(summary['blink_count_proxy']);
        final double durationSec = _toDouble(summary['duration_sec']);

        if (durationSec > 0) {
          values.add(blinkCount / durationSec * 60.0);
        }

        continue;
      }

      if (key == 'blink_rate_per_min_event') {
        final double? eventRate = _toNullableDouble(
          summary['blink_rate_per_min_event'],
        );

        if (eventRate != null) {
          values.add(eventRate);
          continue;
        }

        final double blinkCount = _toDouble(summary['blink_count_event']);
        final double durationSec = _toDouble(summary['duration_sec']);

        if (durationSec > 0) {
          values.add(blinkCount / durationSec * 60.0);
        }

        continue;
      }

      final double? value = _toNullableDouble(summary[key]);

      if (value != null) {
        values.add(value);
      }
    }

    if (values.isEmpty) {
      return null;
    }

    return _round4(_mean(values));
  }

  static double? _facingForwardRatio(List<Map<String, String>> rows) {
    if (rows.isEmpty) {
      return null;
    }

    int valid = 0;
    int facingForward = 0;

    for (final Map<String, String> row in rows) {
      final bool faceDetected = row['face_detected'] == 'true';

      if (!faceDetected) {
        continue;
      }

      final double? yaw = _toNullableDouble(row['yaw_proxy']);
      final double? pitch = _toNullableDouble(row['pitch_proxy']);
      final double? roll = _toNullableDouble(row['roll_proxy_deg']);

      if (yaw == null || pitch == null || roll == null) {
        continue;
      }

      valid += 1;

      if (yaw.abs() <= 15.0 && pitch.abs() <= 15.0 && roll.abs() <= 20.0) {
        facingForward += 1;
      }
    }

    if (valid == 0) {
      return null;
    }

    return facingForward / valid;
  }

  static double? _meanColumn(List<Map<String, String>> rows, String column) {
    final List<double> values = rows
        .map((Map<String, String> row) => _toNullableDouble(row[column]))
        .whereType<double>()
        .toList();

    if (values.isEmpty) {
      return null;
    }

    return _mean(values);
  }

  static double? _stdColumn(List<Map<String, String>> rows, String column) {
    final List<double> values = rows
        .map((Map<String, String> row) => _toNullableDouble(row[column]))
        .whereType<double>()
        .toList();

    if (values.length <= 1) {
      return null;
    }

    return _std(values);
  }

  static Map<String, dynamic> _computeResponseToNameProxy({
    required Map<String, dynamic>? stimulusEvents,
    required Map<String, List<Map<String, String>>> csvRowsByStimulus,
  }) {
    final dynamic rawEvents = stimulusEvents == null
        ? null
        : stimulusEvents['triggered_name_call_events'];

    if (rawEvents is! List) {
      return {
        'schema_version': 'mobile_response_to_name_features_v2',
        'mean_delay_sec': null,
        'response_proportion': null,
        'responded_count': 0,
        'total_name_calls': 0,
        'events': [],
        'proxy_rule': 'No triggered name-call events were available.',
      };
    }

    const double baselineStartOffsetSec = -1.0;
    const double baselineEndOffsetSec = 0.0;
    const double responseStartOffsetSec = 0.3;
    const double responseEndOffsetSec = 4.0;
    const double headChangeThresholdDeg = 8.0;
    const double headVelocityThresholdDegPerSec = 8.0;
    const double gazeShiftThreshold = 0.12;

    final List<double> delays = [];
    final List<Map<String, dynamic>> eventEvidence = [];
    int total = 0;

    for (final dynamic rawEvent in rawEvents) {
      if (rawEvent is! Map) {
        continue;
      }

      total += 1;

      final Map<String, dynamic> event = Map<String, dynamic>.from(rawEvent);

      final String stimulusId =
          event['stimulus_id']?.toString() ??
          event['during_stimulus']?.toString() ??
          '';

      final dynamic actualTriggerTime = event['actual_global_trigger_time_sec'];

      if (actualTriggerTime == null) {
        eventEvidence.add({
          'cue_index': total,
          'stimulus_id': stimulusId,
          'responded': false,
          'reason': 'missing_actual_trigger_time',
        });
        continue;
      }

      final double callTimeSec = _toDouble(actualTriggerTime);

      final List<Map<String, String>> rows =
          csvRowsByStimulus[stimulusId] ?? [];

      final List<Map<String, String>> baselineRows = rows.where((
        Map<String, String> row,
      ) {
        final double? elapsed = _toNullableDouble(row['elapsed_time']);
        if (elapsed == null) return false;
        final double relativeSec = elapsed - callTimeSec;
        return relativeSec >= baselineStartOffsetSec &&
            relativeSec <= baselineEndOffsetSec;
      }).toList();

      final List<Map<String, String>> responseRows = rows.where((
        Map<String, String> row,
      ) {
        final double? elapsed = _toNullableDouble(row['elapsed_time']);
        if (elapsed == null) return false;
        final double relativeSec = elapsed - callTimeSec;
        return relativeSec >= responseStartOffsetSec &&
            relativeSec <= responseEndOffsetSec;
      }).toList();

      final double? baselineYaw = _meanColumn(baselineRows, 'yaw_proxy');
      final double? baselinePitch = _meanColumn(baselineRows, 'pitch_proxy');
      final double? baselineRoll = _meanColumn(baselineRows, 'roll_proxy_deg');
      final double? baselineGazeX = _meanValidGazeColumn(baselineRows, 'gaze_x');
      final double? baselineGazeY = _meanValidGazeColumn(baselineRows, 'gaze_y');

      double? detectedDelay;
      String responseSource = 'none';
      Map<String, dynamic>? detectedEvidence;

      double maxHeadChangeDeg = 0.0;
      double maxHeadVelocity = 0.0;
      double maxGazeShift = 0.0;

      for (final Map<String, String> row in responseRows) {
        final double? elapsed = _toNullableDouble(row['elapsed_time']);
        if (elapsed == null) {
          continue;
        }

        final double afterCall = elapsed - callTimeSec;
        final double? yaw = _toNullableDouble(row['yaw_proxy']);
        final double? pitch = _toNullableDouble(row['pitch_proxy']);
        final double? roll = _toNullableDouble(row['roll_proxy_deg']);
        final double? headVelocity = _toNullableDouble(row['head_movement']);
        final double? gazeX = row['gaze_valid'] == 'true'
            ? _toNullableDouble(row['gaze_x'])
            : null;
        final double? gazeY = row['gaze_valid'] == 'true'
            ? _toNullableDouble(row['gaze_y'])
            : null;

        final double? headChangeDeg = _headPoseChangeDeg(
          baselineYaw: baselineYaw,
          baselinePitch: baselinePitch,
          baselineRoll: baselineRoll,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
        );

        final double? gazeShift = _gazeShift(
          baselineGazeX: baselineGazeX,
          baselineGazeY: baselineGazeY,
          gazeX: gazeX,
          gazeY: gazeY,
        );

        if (headChangeDeg != null && headChangeDeg > maxHeadChangeDeg) {
          maxHeadChangeDeg = headChangeDeg;
        }

        if (headVelocity != null && headVelocity > maxHeadVelocity) {
          maxHeadVelocity = headVelocity;
        }

        if (gazeShift != null && gazeShift > maxGazeShift) {
          maxGazeShift = gazeShift;
        }

        final bool respondedByHeadChange =
            headChangeDeg != null && headChangeDeg >= headChangeThresholdDeg;
        final bool respondedByHeadVelocity = headVelocity != null &&
            headVelocity >= headVelocityThresholdDegPerSec;
        final bool respondedByGazeShift =
            gazeShift != null && gazeShift >= gazeShiftThreshold;

        if (respondedByHeadChange ||
            respondedByHeadVelocity ||
            respondedByGazeShift) {
          detectedDelay = afterCall;
          responseSource = _responseSourceLabel(
            respondedByHeadChange: respondedByHeadChange,
            respondedByHeadVelocity: respondedByHeadVelocity,
            respondedByGazeShift: respondedByGazeShift,
          );
          detectedEvidence = {
            'elapsed_time_sec': _round4(elapsed),
            'response_delay_sec': _round4(afterCall),
            'head_change_deg': headChangeDeg == null
                ? null
                : _round4(headChangeDeg),
            'head_angular_velocity_deg_per_sec': headVelocity == null
                ? null
                : _round4(headVelocity),
            'gaze_shift_normalized': gazeShift == null
                ? null
                : _round4(gazeShift),
            'gaze_valid': gazeX != null && gazeY != null,
          };
          break;
        }
      }

      if (detectedDelay != null) {
        delays.add(detectedDelay);
      }

      eventEvidence.add({
        'cue_index': total,
        'stimulus_id': stimulusId,
        'call_time_sec': _round4(callTimeSec),
        'responded': detectedDelay != null,
        'response_delay_sec': detectedDelay == null
            ? null
            : _round4(detectedDelay),
        'response_source': responseSource,
        'baseline_sample_count': baselineRows.length,
        'response_window_sample_count': responseRows.length,
        'baseline': {
          'yaw_proxy': baselineYaw == null ? null : _round4(baselineYaw),
          'pitch_proxy': baselinePitch == null ? null : _round4(baselinePitch),
          'roll_proxy_deg': baselineRoll == null ? null : _round4(baselineRoll),
          'gaze_x': baselineGazeX == null ? null : _round4(baselineGazeX),
          'gaze_y': baselineGazeY == null ? null : _round4(baselineGazeY),
        },
        'max_post_call_head_change_deg': _round4(maxHeadChangeDeg),
        'max_post_call_head_velocity_deg_per_sec': _round4(maxHeadVelocity),
        'max_post_call_gaze_shift_normalized': _round4(maxGazeShift),
        'detected_frame': detectedEvidence,
      });
    }

    return {
      'schema_version': 'mobile_response_to_name_features_v2',
      'mean_delay_sec': delays.isEmpty ? null : _round4(_mean(delays)),
      'response_proportion': total == 0 ? null : _round4(delays.length / total),
      'responded_count': delays.length,
      'total_name_calls': total,
      'events': eventEvidence,
      'thresholds': {
        'baseline_window_sec': [
          baselineStartOffsetSec,
          baselineEndOffsetSec,
        ],
        'response_window_sec': [
          responseStartOffsetSec,
          responseEndOffsetSec,
        ],
        'head_change_threshold_deg': headChangeThresholdDeg,
        'head_velocity_threshold_deg_per_sec': headVelocityThresholdDegPerSec,
        'gaze_shift_threshold_normalized': gazeShiftThreshold,
      },
      'proxy_rule':
          'Response is detected when post-call head pose change, head angular velocity, or calibrated gaze shift crosses threshold within 0.3–4.0 sec after the cue.',
    };
  }

  static double? _meanValidGazeColumn(
    List<Map<String, String>> rows,
    String column,
  ) {
    final List<double> values = rows
        .where((Map<String, String> row) => row['gaze_valid'] == 'true')
        .map((Map<String, String> row) => _toNullableDouble(row[column]))
        .whereType<double>()
        .toList();

    if (values.isEmpty) {
      return null;
    }

    return _mean(values);
  }

  static double? _headPoseChangeDeg({
    required double? baselineYaw,
    required double? baselinePitch,
    required double? baselineRoll,
    required double? yaw,
    required double? pitch,
    required double? roll,
  }) {
    if (baselineYaw == null ||
        baselinePitch == null ||
        baselineRoll == null ||
        yaw == null ||
        pitch == null ||
        roll == null) {
      return null;
    }

    final double dYaw = yaw - baselineYaw;
    final double dPitch = pitch - baselinePitch;
    final double dRoll = roll - baselineRoll;

    return sqrt((dYaw * dYaw) + (dPitch * dPitch) + (dRoll * dRoll));
  }

  static double? _gazeShift({
    required double? baselineGazeX,
    required double? baselineGazeY,
    required double? gazeX,
    required double? gazeY,
  }) {
    if (baselineGazeX == null ||
        baselineGazeY == null ||
        gazeX == null ||
        gazeY == null) {
      return null;
    }

    final double dx = gazeX - baselineGazeX;
    final double dy = gazeY - baselineGazeY;

    return sqrt((dx * dx) + (dy * dy));
  }

  static String _responseSourceLabel({
    required bool respondedByHeadChange,
    required bool respondedByHeadVelocity,
    required bool respondedByGazeShift,
  }) {
    final List<String> parts = [];

    if (respondedByHeadChange) {
      parts.add('head_pose_change');
    }

    if (respondedByHeadVelocity) {
      parts.add('head_angular_velocity');
    }

    if (respondedByGazeShift) {
      parts.add('calibrated_gaze_shift');
    }

    return parts.isEmpty ? 'none' : parts.join('+');
  }

  static dynamic _valueFromNested(
    Map<String, dynamic>? map,
    List<String> path,
  ) {
    dynamic current = map;

    for (final String key in path) {
      if (current is! Map) {
        return null;
      }

      current = current[key];
    }

    if (current is num) {
      return _round4(current.toDouble());
    }

    return current;
  }

  static List<Map<String, dynamic>> _tuningBacklog() {
    return [
      {
        'area': 'true_gaze_features',
        'needed_for': [
          PaperFeatureNames.gazePercentSocial,
          PaperFeatureNames.gazeSilhouetteScore,
          PaperFeatureNames.attentionToSpeech,
        ],
        'improvement':
            'Current implementation uses calibrated MediaPipe iris landmarks mapped to stimulus AOIs. For stronger paper-faithfulness, validate gaze accuracy against known screen targets and improve calibration/modeling.',
      },
      {
        'area': 'eyebrow_and_mouth_complexity',
        'needed_for': [
          PaperFeatureNames.eyebrowComplexitySocialMovies,
          PaperFeatureNames.eyebrowComplexityNonsocialMovies,
          PaperFeatureNames.mouthComplexitySocialMovies,
          PaperFeatureNames.mouthComplexityNonsocialMovies,
        ],
        'improvement':
            'Enable face contours/landmarks or MediaPipe Face Mesh to compute landmark dynamics instead of smile-probability proxy.',
      },
      {
        'area': 'response_to_name',
        'needed_for': [
          PaperFeatureNames.responseToNameDelaySec,
          PaperFeatureNames.responseToNameProportion,
        ],
        'improvement':
            'Record exact cue trigger wall-time during playback and compute orientation/attention change after each call.',
      },
      {
        'area': 'touch_force',
        'needed_for': [PaperFeatureNames.popTheBubblesAverageAppliedForce],
        'improvement':
            'Use Listener with PointerDownEvent/PointerMoveEvent pressure, radiusMajor, radiusMinor, and device support checks to estimate touch force.',
      },
    ];
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      if (value.trim().isEmpty) {
        return null;
      }

      return double.tryParse(value.trim());
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

  static Map<String, Map<String, dynamic>> _stimulusByIdFromVideoTest(
    Map<String, dynamic>? videoTest,
  ) {
    final Map<String, Map<String, dynamic>> result = {};

    final dynamic rawResults = videoTest == null
        ? null
        : videoTest['stimulus_results'];

    if (rawResults is! List) {
      return result;
    }

    for (final dynamic rawItem in rawResults) {
      if (rawItem is! Map) {
        continue;
      }

      final Map<String, dynamic> item = Map<String, dynamic>.from(rawItem);

      if (item['stimulus'] is! Map) {
        continue;
      }

      final Map<String, dynamic> stimulus = Map<String, dynamic>.from(
        item['stimulus'] as Map,
      );

      final String stimulusId = stimulus['id']?.toString() ?? '';

      if (stimulusId.isEmpty) {
        continue;
      }

      result[stimulusId] = stimulus;
    }

    return result;
  }

  static double? _computeGazePercentSocialProxy({
    required Map<String, List<Map<String, String>>> csvRowsByStimulus,
    required Map<String, Map<String, dynamic>> stimulusById,
    required List<String> stimulusIds,
  }) {
    int socialCount = 0;
    int totalCount = 0;

    for (final String stimulusId in stimulusIds) {
      final Map<String, dynamic>? stimulus = stimulusById[stimulusId];

      if (stimulus == null) {
        continue;
      }

      final Map<String, dynamic>? socialAoi = _aoiMap(stimulus['social_aoi']);
      final Map<String, dynamic>? nonsocialAoi = _aoiMap(
        stimulus['nonsocial_aoi'],
      );

      if (socialAoi == null || nonsocialAoi == null) {
        continue;
      }

      final List<Map<String, String>> rows =
          csvRowsByStimulus[stimulusId] ?? [];

      for (final Map<String, String> row in rows) {
        final _GazeProxyPoint? point = _estimateGazeProxyPoint(
          row: row,
          socialAoi: socialAoi,
          nonsocialAoi: nonsocialAoi,
        );

        if (point == null) {
          continue;
        }

        totalCount += 1;

        if (point.label == 'social') {
          socialCount += 1;
        }
      }
    }

    if (totalCount == 0) {
      return null;
    }

    return _round4(socialCount / totalCount);
  }

  static double? _computeGazeSilhouetteProxy({
    required Map<String, List<Map<String, String>>> csvRowsByStimulus,
    required Map<String, Map<String, dynamic>> stimulusById,
    required List<String> stimulusIds,
  }) {
    final List<_GazeProxyPoint> points = [];

    for (final String stimulusId in stimulusIds) {
      final Map<String, dynamic>? stimulus = stimulusById[stimulusId];

      if (stimulus == null) {
        continue;
      }

      final Map<String, dynamic>? socialAoi = _aoiMap(stimulus['social_aoi']);
      final Map<String, dynamic>? nonsocialAoi = _aoiMap(
        stimulus['nonsocial_aoi'],
      );

      if (socialAoi == null || nonsocialAoi == null) {
        continue;
      }

      final List<Map<String, String>> rows =
          csvRowsByStimulus[stimulusId] ?? [];

      for (final Map<String, String> row in rows) {
        final _GazeProxyPoint? point = _estimateGazeProxyPoint(
          row: row,
          socialAoi: socialAoi,
          nonsocialAoi: nonsocialAoi,
        );

        if (point != null) {
          points.add(point);
        }
      }
    }

    final int socialCount = points
        .where((_GazeProxyPoint point) => point.label == 'social')
        .length;

    final int nonsocialCount = points
        .where((_GazeProxyPoint point) => point.label == 'nonsocial')
        .length;

    if (socialCount < 2 || nonsocialCount < 2) {
      return null;
    }

    final List<double> silhouettes = [];

    for (int i = 0; i < points.length; i++) {
      final _GazeProxyPoint current = points[i];

      final List<_GazeProxyPoint> sameCluster = points
          .where(
            (_GazeProxyPoint point) =>
                point.label == current.label && point != current,
          )
          .toList();

      final List<_GazeProxyPoint> otherCluster = points
          .where((_GazeProxyPoint point) => point.label != current.label)
          .toList();

      if (sameCluster.isEmpty || otherCluster.isEmpty) {
        continue;
      }

      final double a = _mean(
        sameCluster
            .map(
              (_GazeProxyPoint point) =>
                  _distance2d(current.x, current.y, point.x, point.y),
            )
            .toList(),
      );

      final double b = _mean(
        otherCluster
            .map(
              (_GazeProxyPoint point) =>
                  _distance2d(current.x, current.y, point.x, point.y),
            )
            .toList(),
      );

      final double denominator = max(a, b);

      if (denominator <= 0) {
        continue;
      }

      silhouettes.add((b - a) / denominator);
    }

    if (silhouettes.isEmpty) {
      return null;
    }

    return _round4(_mean(silhouettes));
  }

  static _GazeProxyPoint? _estimateGazeProxyPoint({
    required Map<String, String> row,
    required Map<String, dynamic> socialAoi,
    required Map<String, dynamic> nonsocialAoi,
  }) {
    if (row['gaze_valid'] != 'true') {
      return null;
    }

    final double? gazeX = _toNullableDouble(row['gaze_x']);
    final double? gazeY = _toNullableDouble(row['gaze_y']);

    if (gazeX == null || gazeY == null) {
      return null;
    }

    String label;

    final bool insideSocial = _pointInsideAoi(
      x: gazeX,
      y: gazeY,
      aoi: socialAoi,
    );

    final bool insideNonsocial = _pointInsideAoi(
      x: gazeX,
      y: gazeY,
      aoi: nonsocialAoi,
    );

    if (insideSocial && !insideNonsocial) {
      label = 'social';
    } else if (insideNonsocial && !insideSocial) {
      label = 'nonsocial';
    } else {
      final List<double> socialCenter = _aoiCenter(socialAoi);
      final List<double> nonsocialCenter = _aoiCenter(nonsocialAoi);

      final double socialDistance = _distance2d(
        gazeX,
        gazeY,
        socialCenter[0],
        socialCenter[1],
      );

      final double nonsocialDistance = _distance2d(
        gazeX,
        gazeY,
        nonsocialCenter[0],
        nonsocialCenter[1],
      );

      label = socialDistance <= nonsocialDistance ? 'social' : 'nonsocial';
    }

    return _GazeProxyPoint(x: gazeX, y: gazeY, label: label);
  }

  static Map<String, dynamic>? _aoiMap(dynamic value) {
    if (value is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(value);
  }

  static bool _pointInsideAoi({
    required double x,
    required double y,
    required Map<String, dynamic> aoi,
  }) {
    final double xMin = _toDouble(aoi['x_min']);
    final double yMin = _toDouble(aoi['y_min']);
    final double xMax = _toDouble(aoi['x_max']);
    final double yMax = _toDouble(aoi['y_max']);

    return x >= xMin && x <= xMax && y >= yMin && y <= yMax;
  }

  static List<double> _aoiCenter(Map<String, dynamic> aoi) {
    final double xMin = _toDouble(aoi['x_min']);
    final double yMin = _toDouble(aoi['y_min']);
    final double xMax = _toDouble(aoi['x_max']);
    final double yMax = _toDouble(aoi['y_max']);

    return [(xMin + xMax) / 2.0, (yMin + yMax) / 2.0];
  }

  static double _distance2d(double x1, double y1, double x2, double y2) {
    final double dx = x1 - x2;
    final double dy = y1 - y2;

    return sqrt((dx * dx) + (dy * dy));
  }
}

class _GazeProxyPoint {
  _GazeProxyPoint({required this.x, required this.y, required this.label});

  final double x;
  final double y;
  final String label;
}
