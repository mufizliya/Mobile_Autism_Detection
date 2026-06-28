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
      source: 'mobile_framewise_csv_proxy',
      note:
          'Proxy for paper feature. Computed as proportion of face-detected frames with modest yaw/pitch during social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.facingForwardNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        _facingForwardRatio,
      ),
      source: 'mobile_framewise_csv_proxy',
      note:
          'Proxy for paper feature. Computed as proportion of face-detected frames with modest yaw/pitch during nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.gazePercentSocial,
      value: null,
      source: 'missing_true_gaze_to_screen_aoi',
      note:
          'Paper feature requires gaze coordinates mapped to social/nonsocial AOIs on the stimulus screen. Current ML Kit recorder gives face/head proxy signals, not true screen gaze.',
    );

    setFeature(
      name: PaperFeatureNames.gazeSilhouetteScore,
      value: null,
      source: 'missing_true_gaze_to_screen_aoi',
      note:
          'Paper feature requires true gaze clustering/separation between social and nonsocial AOIs. Current data cannot compute it faithfully.',
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
      source: 'mobile_head_movement_after_name_call_proxy',
      note:
          'Proxy only. Estimated from first post-name-call head movement response in framewise logs.',
    );

    setFeature(
      name: PaperFeatureNames.responseToNameProportion,
      value: responseToName['response_proportion'],
      source: 'mobile_head_movement_after_name_call_proxy',
      note:
          'Proxy only. Proportion of name calls with post-call head movement response.',
    );

    setFeature(
      name: PaperFeatureNames.blinkRateSocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allSocialLikeStimuli,
        'blink_rate_per_min_proxy',
      ),
      source: 'mobile_eye_open_probability_proxy',
      note:
          'Proxy blink rate from eye-open probability transitions during social/mixed/speech stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.blinkRateNonsocialMovies,
      value: _meanSummaryValueByStimuli(
        summariesByStimulus,
        allNonsocialLikeStimuli,
        'blink_rate_per_min_proxy',
      ),
      source: 'mobile_eye_open_probability_proxy',
      note:
          'Proxy blink rate from eye-open probability transitions during nonsocial/mixed stimuli.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementSocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) => _meanColumn(rows, 'head_movement'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note:
          'Proxy for paper head movement. Uses face bounding-box center movement between frames.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) => _meanColumn(rows, 'head_movement'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note:
          'Proxy for paper head movement. Uses face bounding-box center movement between frames.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementComplexitySocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'head_movement'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note:
          'Proxy complexity. Uses standard deviation of frame-to-frame head movement.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementComplexityNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'head_movement'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note:
          'Proxy complexity. Uses standard deviation of frame-to-frame head movement.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementAccelerationSocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) =>
            _meanColumn(rows, 'head_acceleration'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note: 'Proxy acceleration. Uses change in frame-to-frame head movement.',
    );

    setFeature(
      name: PaperFeatureNames.headMovementAccelerationNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) =>
            _meanColumn(rows, 'head_acceleration'),
      ),
      source: 'mobile_face_center_motion_proxy',
      note: 'Proxy acceleration. Uses change in frame-to-frame head movement.',
    );

    setFeature(
      name: PaperFeatureNames.mouthComplexitySocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allSocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'mouth_open'),
      ),
      source: 'mobile_smile_probability_proxy',
      note:
          'Proxy for mouth dynamics. Uses standard deviation of ML Kit smiling probability.',
    );

    setFeature(
      name: PaperFeatureNames.mouthComplexityNonsocialMovies,
      value: _meanForStimuli(
        csvRowsByStimulus,
        allNonsocialLikeStimuli,
        (List<Map<String, String>> rows) => _stdColumn(rows, 'mouth_open'),
      ),
      source: 'mobile_smile_probability_proxy',
      note:
          'Proxy for mouth dynamics. Uses standard deviation of ML Kit smiling probability.',
    );

    setFeature(
      name: PaperFeatureNames.eyebrowComplexitySocialMovies,
      value: null,
      source: 'missing_eyebrow_landmarks',
      note:
          'Paper feature requires eyebrow landmark dynamics. Current ML Kit setup does not export eyebrow landmarks.',
    );

    setFeature(
      name: PaperFeatureNames.eyebrowComplexityNonsocialMovies,
      value: null,
      source: 'missing_eyebrow_landmarks',
      note:
          'Paper feature requires eyebrow landmark dynamics. Current ML Kit setup does not export eyebrow landmarks.',
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

      if (yaw == null || pitch == null) {
        continue;
      }

      valid += 1;

      if (yaw.abs() <= 20.0 && pitch.abs() <= 20.0) {
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
        'mean_delay_sec': null,
        'response_proportion': null,
        'responded_count': 0,
        'total_name_calls': 0,
      };
    }

    final List<double> delays = [];
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
        continue;
      }

      final double callTimeSec = _toDouble(actualTriggerTime);

      final List<Map<String, String>> rows =
          csvRowsByStimulus[stimulusId] ?? [];

      double? detectedDelay;

      for (final Map<String, String> row in rows) {
        final double? elapsed = _toNullableDouble(row['elapsed_time']);
        final double? movement = _toNullableDouble(row['head_movement']);

        if (elapsed == null || movement == null) {
          continue;
        }

        final double afterCall = elapsed - callTimeSec;

        if (afterCall < 0 || afterCall > 4.0) {
          continue;
        }

        if (movement >= 5.0) {
          detectedDelay = afterCall;
          break;
        }
      }

      if (detectedDelay != null) {
        delays.add(detectedDelay);
      }
    }

    return {
      'mean_delay_sec': delays.isEmpty ? null : _round4(_mean(delays)),
      'response_proportion': total == 0 ? null : _round4(delays.length / total),
      'responded_count': delays.length,
      'total_name_calls': total,
      'proxy_rule':
          'First frame within 4 sec after call where head_movement >= 5 px.',
    };
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
            'Add gaze estimation or eye landmark pipeline and map gaze to stimulus AOIs.',
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
}
