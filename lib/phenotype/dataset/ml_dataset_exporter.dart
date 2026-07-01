import 'dart:io';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../models/paper_feature_names.dart';

class MlDatasetExporter {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final Map<String, dynamic>? childInfo =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.childInfo,
    );

    final Map<String, dynamic>? scqResults =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.scqResults,
    );

    final Map<String, dynamic>? paperAlignedFeatures =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.paperAlignedFeatures,
    );

    final Map<String, dynamic>? paperFeatureCoverage =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.paperFeatureCoverage,
    );

    final Map<String, dynamic>? featureReliability =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.featureReliability,
    );

    final Map<String, dynamic>? sessionQuality =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.sessionQuality,
    );

    final Map<String, dynamic>? framewiseSignals =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.framewiseFaceSignals,
    );

    final Map<String, dynamic>? calibratedGazeFrames =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.calibratedGazeFrames,
    );

    final Map<String, dynamic>? gazeCalibrationQuality =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.gazeCalibrationQuality,
    );

    final Map<String, dynamic>? attentionToSpeechFeatures =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.attentionToSpeechFeatures,
    );

    final Map<String, dynamic>? responseToNameFeatures =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.responseToNameFeatures,
    );

    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.gameMetrics,
    );

    final Map<String, dynamic> values = _map(
      paperAlignedFeatures?['values'],
    );

    final Map<String, dynamic> sources = _map(
      paperAlignedFeatures?['sources'],
    );

    final Map<String, dynamic> reliabilityFeatures = _map(
      featureReliability?['features'],
    );

    final Map<String, dynamic> qualityContext = _map(
      featureReliability?['quality_context'],
    );

    final Map<String, dynamic> framewiseSummary = _map(
      framewiseSignals?['summary'],
    );

    final Map<String, dynamic> gazeClipping = _map(
      calibratedGazeFrames?['gaze_clipping'],
    );

    final Map<String, dynamic> verticalStabilization = _map(
      calibratedGazeFrames?['vertical_stabilization'],
    );

    final Map<String, dynamic> touchFeatures = _map(
      gameMetrics?['touch_features'],
    );

    final Map<String, dynamic> row = {
      'schema_version': 'mobile_ml_dataset_row_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'dataset_row_type': 'one_row_per_completed_session',
      'session_id': sessionDir.uri.pathSegments.isEmpty
          ? sessionDir.path
          : sessionDir.uri.pathSegments.last,
      'session_path_local': sessionDir.path,
      'diagnostic_label_available': false,
      'diagnostic_label': null,
      'clinical_use_allowed': false,
      'clinical_use_note':
          'Research dataset row only. Not a clinical diagnostic output.',
      'child_name_hash_or_id': childInfo?['name'],
      'child_age_raw': childInfo?['age'],
      'child_age_years': _numberOrNull(childInfo?['age']),
      'child_gender': childInfo?['gender'],
      'scq_score': _numberOrNull(scqResults?['scq_score']),
      'scq_outcome': scqResults?['outcome'],
      'session_quality_status': sessionQuality?['overall_status'],
      'session_quality_passed': sessionQuality?['overall_status'] == 'valid',
      'critical_failure_count': _numberOrNull(
        sessionQuality?['critical_failure_count'],
      ),
      'warning_failure_count': _numberOrNull(
        sessionQuality?['warning_failure_count'],
      ),
      'paper_feature_available_count': _numberOrNull(
        paperFeatureCoverage?['available_feature_count'],
      ),
      'paper_feature_missing_count': _numberOrNull(
        paperFeatureCoverage?['missing_feature_count'],
      ),
      'paper_feature_total_count': _numberOrNull(
        paperFeatureCoverage?['total_expected_feature_count'],
      ),
      'feature_reliability_computed_direct_count': _numberOrNull(
        _map(featureReliability?['counts'])['computed_direct'],
      ),
      'feature_reliability_computed_close_proxy_count': _numberOrNull(
        _map(featureReliability?['counts'])['computed_close_proxy'],
      ),
      'feature_reliability_computed_proxy_count': _numberOrNull(
        _map(featureReliability?['counts'])['computed_proxy'],
      ),
      'feature_reliability_missing_device_limitation_count': _numberOrNull(
        _map(featureReliability?['counts'])['missing_device_limitation'],
      ),
      'framewise_frame_count': _numberOrNull(framewiseSummary['total_frame_count']) ??
          _numberOrNull(_map(qualityContext['framewise'])['frame_count']),
      'face_presence_ratio': _numberOrNull(
            framewiseSummary['face_presence_ratio'],
          ) ??
          _numberOrNull(_map(qualityContext['framewise'])['face_presence_ratio']),
      'iris_presence_ratio': _numberOrNull(
            framewiseSummary['iris_presence_ratio'],
          ) ??
          _numberOrNull(_map(qualityContext['framewise'])['iris_presence_ratio']),
      'gaze_calibration_status': gazeCalibrationQuality?['overall_status'] ??
          _map(qualityContext['gaze'])['calibration_status'],
      'valid_gaze_ratio': _numberOrNull(
        calibratedGazeFrames?['valid_gaze_ratio'],
      ),
      'gaze_x_clipped_ratio': _numberOrNull(gazeClipping['x_clipped_ratio']),
      'gaze_y_clipped_ratio': _numberOrNull(gazeClipping['y_clipped_ratio']),
      'gaze_clipping_status': gazeClipping['status'],
      'gaze_y_mapping_mode': calibratedGazeFrames?['gaze_y_mapping_mode'],
      'gaze_vertical_stabilization_enabled':
          verticalStabilization['enabled'] == true,
      'attention_to_speech_method': attentionToSpeechFeatures?['method'],
      'attention_to_speech_valid_gaze_frame_count': _numberOrNull(
        attentionToSpeechFeatures?['valid_speech_gaze_frame_count'],
      ),
      'attention_to_speech_gaze_coverage_ratio': _numberOrNull(
        attentionToSpeechFeatures?['speech_gaze_coverage_ratio'],
      ),
      'turn_taking_speaker_selectivity_score': _numberOrNull(
        attentionToSpeechFeatures?['turn_taking_speaker_selectivity_score'],
      ),
      'turn_taking_horizontal_speaker_selectivity_score': _numberOrNull(
        attentionToSpeechFeatures?
            ['turn_taking_horizontal_speaker_selectivity_score'],
      ),
      'response_to_name_total_calls': _numberOrNull(
        responseToNameFeatures?['total_name_calls'],
      ),
      'response_to_name_responded_count': _numberOrNull(
        responseToNameFeatures?['responded_count'],
      ),
      'bubble_game_score': _numberOrNull(gameMetrics?['score']),
      'bubble_game_total_reactions': _numberOrNull(gameMetrics?['total_reactions']),
      'touch_force_available': gameMetrics?['touch_force_available'] == true,
      'touch_force_unavailable_reason':
          touchFeatures['touch_force_unavailable_reason'],
    };

    for (final String featureName in PaperFeatureNames.all) {
      final Map<String, dynamic> reliability = _map(
        reliabilityFeatures[featureName],
      );

      final dynamic value = values[featureName];

      row[featureName] = value;
      row['${featureName}_available'] = value != null;
      row['${featureName}_source'] =
          reliability['source'] ?? sources[featureName];
      row['${featureName}_status'] = reliability['status'];
      row['${featureName}_confidence'] = reliability['confidence'];
    }

    final Map<String, dynamic> payload = {
      'schema_version': 'mobile_ml_dataset_export_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'intended_use':
          'Research-only ML dataset row for paper-aligned mobile digital phenotyping features.',
      'clinical_use_allowed': false,
      'clinical_use_warning':
          'Do not use for diagnosis, triage, treatment decisions, or clinical claims without prospective validation, ethics approval, and applicable regulatory review.',
      'row': row,
      'feature_columns': PaperFeatureNames.all,
      'quality_columns': _qualityColumnNames,
      'source_files': {
        SessionFileNames.childInfo: childInfo != null,
        SessionFileNames.scqResults: scqResults != null,
        SessionFileNames.paperAlignedFeatures: paperAlignedFeatures != null,
        SessionFileNames.paperFeatureCoverage: paperFeatureCoverage != null,
        SessionFileNames.featureReliability: featureReliability != null,
        SessionFileNames.sessionQuality: sessionQuality != null,
        SessionFileNames.framewiseFaceSignals: framewiseSignals != null,
        SessionFileNames.calibratedGazeFrames: calibratedGazeFrames != null,
        SessionFileNames.attentionToSpeechFeatures:
            attentionToSpeechFeatures != null,
        SessionFileNames.responseToNameFeatures: responseToNameFeatures != null,
        SessionFileNames.gameMetrics: gameMetrics != null,
      },
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.mlDatasetRowJson,
      data: payload,
    );

    final List<String> headers = _csvHeaders();

    await SessionService.saveCsv(
      sessionDir: sessionDir,
      fileName: SessionFileNames.mlDatasetRowCsv,
      headers: headers,
      rows: [
        headers.map((String key) => row[key]).toList(),
      ],
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.mlDatasetSchema,
      data: _schemaPayload(headers),
    );

    return payload;
  }

  static List<String> _csvHeaders() {
    final List<String> headers = [
      ..._metadataColumnNames,
      ..._qualityColumnNames,
    ];

    for (final String featureName in PaperFeatureNames.all) {
      headers.add(featureName);
      headers.add('${featureName}_available');
      headers.add('${featureName}_status');
      headers.add('${featureName}_confidence');
      headers.add('${featureName}_source');
    }

    return headers;
  }

  static Map<String, dynamic> _schemaPayload(List<String> headers) {
    return {
      'schema_version': 'mobile_ml_dataset_schema_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'row_granularity': 'one row per completed session',
      'csv_file': SessionFileNames.mlDatasetRowCsv,
      'json_file': SessionFileNames.mlDatasetRowJson,
      'column_count': headers.length,
      'columns': headers,
      'paper_feature_columns': PaperFeatureNames.all,
      'label_policy': {
        'diagnostic_label_available':
            'false unless an externally verified clinical/research label is added later.',
        'diagnostic_label':
            'null in app-generated rows. Do not infer labels from SCQ or app features.',
      },
      'missing_value_policy': {
        'null':
            'Feature unavailable or not computable for this session. Check *_status and *_confidence columns.',
        'paper_pop_the_bubbles_average_applied_force':
            'Usually null on devices with unusable touch pressure; do not impute as zero by default.',
      },
      'clinical_use_warning':
          'This schema is for research/export. It is not a validated clinical diagnostic dataset by itself.',
    };
  }

  static const List<String> _metadataColumnNames = [
    'schema_version',
    'generated_at',
    'dataset_row_type',
    'session_id',
    'session_path_local',
    'diagnostic_label_available',
    'diagnostic_label',
    'clinical_use_allowed',
    'clinical_use_note',
    'child_name_hash_or_id',
    'child_age_raw',
    'child_age_years',
    'child_gender',
    'scq_score',
    'scq_outcome',
  ];

  static const List<String> _qualityColumnNames = [
    'session_quality_status',
    'session_quality_passed',
    'critical_failure_count',
    'warning_failure_count',
    'paper_feature_available_count',
    'paper_feature_missing_count',
    'paper_feature_total_count',
    'feature_reliability_computed_direct_count',
    'feature_reliability_computed_close_proxy_count',
    'feature_reliability_computed_proxy_count',
    'feature_reliability_missing_device_limitation_count',
    'framewise_frame_count',
    'face_presence_ratio',
    'iris_presence_ratio',
    'gaze_calibration_status',
    'valid_gaze_ratio',
    'gaze_x_clipped_ratio',
    'gaze_y_clipped_ratio',
    'gaze_clipping_status',
    'gaze_y_mapping_mode',
    'gaze_vertical_stabilization_enabled',
    'attention_to_speech_method',
    'attention_to_speech_valid_gaze_frame_count',
    'attention_to_speech_gaze_coverage_ratio',
    'turn_taking_speaker_selectivity_score',
    'turn_taking_horizontal_speaker_selectivity_score',
    'response_to_name_total_calls',
    'response_to_name_responded_count',
    'bubble_game_score',
    'bubble_game_total_reactions',
    'touch_force_available',
    'touch_force_unavailable_reason',
  ];

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  static double? _numberOrNull(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }
}
