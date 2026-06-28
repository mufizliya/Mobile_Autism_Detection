import 'dart:io';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';

class SessionQualityValidator {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final List<FileSystemEntity> entities = await sessionDir.list().toList();

    final List<String> allFiles = entities
        .whereType<File>()
        .map((File file) => file.uri.pathSegments.last)
        .toList()
      ..sort();

    final Map<String, dynamic>? framewiseFaceSignals =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.framewiseFaceSignals,
    );

    final Map<String, dynamic>? stimulusEvents =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.stimulusEvents,
    );

    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.gameMetrics,
    );

    final Map<String, dynamic>? paperFeatureCoverage =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.paperFeatureCoverage,
    );

    final List<String> framewiseCsvFiles = allFiles
        .where((String fileName) => fileName.endsWith('_framewise_log.csv'))
        .toList();

    final List<String> framewiseSummaryFiles = allFiles
        .where(
          (String fileName) => fileName.endsWith('_framewise_summary.json'),
        )
        .toList();

    final List<Map<String, dynamic>> checks = [];

    void addCheck({
      required String id,
      required bool passed,
      required String severity,
      required String message,
      dynamic value,
      dynamic expected,
    }) {
      checks.add({
        'id': id,
        'passed': passed,
        'severity': severity,
        'message': message,
        'value': value,
        'expected': expected,
      });
    }

    final int frameCount = _toInt(framewiseFaceSignals?['frame_count']);

    final Map<String, dynamic> frameSummary =
        framewiseFaceSignals?['summary'] is Map
            ? Map<String, dynamic>.from(framewiseFaceSignals!['summary'] as Map)
            : <String, dynamic>{};

    final double facePresenceRatio = _toDouble(
      frameSummary['face_presence_ratio'],
    );

    addCheck(
      id: 'framewise_face_signals_exists',
      passed: framewiseFaceSignals != null,
      severity: 'critical',
      message: 'framewise_face_signals.json should exist.',
      value: framewiseFaceSignals != null,
      expected: true,
    );

    addCheck(
      id: 'frame_count_minimum',
      passed: frameCount >= 150,
      severity: 'critical',
      message:
          'Expected enough sampled frames for approximately 90 seconds at 500 ms sampling.',
      value: frameCount,
      expected: '>= 150',
    );

    addCheck(
      id: 'face_presence_ratio',
      passed: facePresenceRatio >= 0.75,
      severity: 'critical',
      message:
          'Face should be visible in most frames for reliable face-derived phenotypes.',
      value: facePresenceRatio,
      expected: '>= 0.75',
    );

    addCheck(
      id: 'framewise_csv_count',
      passed: framewiseCsvFiles.length == 9,
      severity: 'critical',
      message: 'Expected 9 per-stimulus framewise CSV files.',
      value: framewiseCsvFiles.length,
      expected: 9,
    );

    addCheck(
      id: 'framewise_summary_count',
      passed: framewiseSummaryFiles.length == 9,
      severity: 'critical',
      message: 'Expected 9 per-stimulus framewise summary JSON files.',
      value: framewiseSummaryFiles.length,
      expected: 9,
    );

    final dynamic rawTriggeredEvents =
        stimulusEvents == null ? null : stimulusEvents['triggered_name_call_events'];

    final List<dynamic> triggeredEvents =
        rawTriggeredEvents is List ? rawTriggeredEvents : <dynamic>[];

    final int observedNameCalls = triggeredEvents.where(
      (dynamic item) {
        if (item is! Map) {
          return false;
        }

        return item['triggered'] == true &&
            item['actual_global_trigger_time_sec'] != null;
      },
    ).length;

    addCheck(
      id: 'actual_name_call_triggers',
      passed: observedNameCalls == 3,
      severity: 'warning',
      message:
          'Expected all 3 name-call cues to be observed during actual playback.',
      value: observedNameCalls,
      expected: 3,
    );

    final int score = _toInt(gameMetrics?['score']);
    final int totalReactions = _toInt(gameMetrics?['total_reactions']);

    addCheck(
      id: 'bubble_game_completed',
      passed: gameMetrics != null && totalReactions > 0,
      severity: 'critical',
      message: 'Bubble game should generate game_metrics.json with reactions.',
      value: {
        'game_metrics_exists': gameMetrics != null,
        'total_reactions': totalReactions,
        'score': score,
      },
      expected: 'game_metrics exists and total_reactions > 0',
    );

    final Map<String, dynamic> touchFeatures =
        gameMetrics?['touch_features'] is Map
            ? Map<String, dynamic>.from(gameMetrics!['touch_features'] as Map)
            : <String, dynamic>{};

    addCheck(
      id: 'touch_force_availability',
      passed: touchFeatures['touch_force_available'] == true,
      severity: 'info',
      message:
          'Touch force is optional. If false, the device likely reports constant or unusable pressure.',
      value: {
        'touch_force_available': touchFeatures['touch_force_available'],
        'touch_average_applied_force':
            touchFeatures['touch_average_applied_force'],
        'touch_applied_force_std': touchFeatures['touch_applied_force_std'],
        'unavailable_reason': touchFeatures['touch_force_unavailable_reason'],
      },
      expected: 'true if device supports usable pressure variation',
    );

    final int availableFeatureCount = _toInt(
      paperFeatureCoverage?['available_feature_count'],
    );

    final int missingFeatureCount = _toInt(
      paperFeatureCoverage?['missing_feature_count'],
    );

    addCheck(
      id: 'paper_feature_coverage',
      passed: availableFeatureCount >= 18,
      severity: 'warning',
      message:
          'Paper-aligned feature coverage should be at least 18/23 with current mobile proxy pipeline.',
      value: {
        'available_feature_count': availableFeatureCount,
        'missing_feature_count': missingFeatureCount,
      },
      expected: '>= 18 available features',
    );

    final List<Map<String, dynamic>> failedCriticalChecks = checks
        .where(
          (Map<String, dynamic> check) =>
              check['passed'] == false && check['severity'] == 'critical',
        )
        .toList();

    final List<Map<String, dynamic>> failedWarningChecks = checks
        .where(
          (Map<String, dynamic> check) =>
              check['passed'] == false && check['severity'] == 'warning',
        )
        .toList();

    String overallStatus;

    if (failedCriticalChecks.isNotEmpty) {
      overallStatus = 'failed';
    } else if (failedWarningChecks.isNotEmpty) {
      overallStatus = 'warning';
    } else {
      overallStatus = 'valid';
    }

    final Map<String, dynamic> quality = {
      'schema_version': 'python_mobile_replica_session_quality_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'overall_status': overallStatus,
      'checks': checks,
      'summary': {
        'total_checks': checks.length,
        'failed_critical_count': failedCriticalChecks.length,
        'failed_warning_count': failedWarningChecks.length,
        'frame_count': frameCount,
        'face_presence_ratio': facePresenceRatio,
        'framewise_csv_count': framewiseCsvFiles.length,
        'framewise_summary_count': framewiseSummaryFiles.length,
        'observed_name_call_count': observedNameCalls,
        'bubble_score': score,
        'bubble_total_reactions': totalReactions,
        'available_paper_feature_count': availableFeatureCount,
        'missing_paper_feature_count': missingFeatureCount,
      },
      'interpretation': _interpretation(overallStatus),
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.sessionQuality,
      data: quality,
    );

    return quality;
  }

  static String _interpretation(String status) {
    if (status == 'valid') {
      return 'Session passed all critical and warning checks. It is suitable for paper-aligned phenotype mapping.';
    }

    if (status == 'warning') {
      return 'Session passed critical checks but has warnings. Phenotype outputs can be generated, but should be reviewed before analysis.';
    }

    return 'Session failed one or more critical checks. Do not use this run for analysis without repeating the session.';
  }

  static int _toInt(dynamic value) {
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

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }
}