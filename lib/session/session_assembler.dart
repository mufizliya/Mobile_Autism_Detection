import 'dart:io';

import 'session_file_names.dart';
import 'session_service.dart';
import '../phenotype/mappers/paper_phenotype_mapper.dart';
import '../phenotype/validation/session_quality_validator.dart';
import '../phenotype/validation/feature_reliability_builder.dart';
import '../phenotype/dataset/ml_dataset_exporter.dart';
import '../phenotype/model/prototype_model_prediction_service.dart';

class SessionAssembler {
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

    final Map<String, dynamic>? videoTest =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.videoTest,
        );

    final Map<String, dynamic>? stimulusEvents =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.stimulusEvents,
        );

    final Map<String, dynamic>? stimulusProtocolSummary =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.stimulusProtocolSummary,
        );

    final Map<String, dynamic>? framewiseFaceSignals =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.framewiseFaceSignals,
        );
    final Map<String, dynamic>? gazeCalibration =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gazeCalibration,
        );

    final Map<String, dynamic>? gazeCalibrationQuality =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gazeCalibrationQuality,
        );

    final Map<String, dynamic>? calibratedGazeFrames =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.calibratedGazeFrames,
        );
    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gameMetrics,
        );
    final Map<String, dynamic> phenotypeOutputs =
        await PaperPhenotypeMapper.buildAndSave(sessionDir: sessionDir);
    final Map<String, dynamic> sessionQuality =
        await SessionQualityValidator.buildAndSave(sessionDir: sessionDir);
    final Map<String, dynamic> featureReliability =
        await FeatureReliabilityBuilder.buildAndSave(sessionDir: sessionDir);

    final Map<String, dynamic> mlDatasetExport =
        await MlDatasetExporter.buildAndSave(sessionDir: sessionDir);

    final Map<String, dynamic> prototypeModelPrediction =
        await PrototypeModelPredictionService.buildAndSave(
      sessionDir: sessionDir,
    );

    final Map<String, dynamic>? attentionToSpeechFeatures =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.attentionToSpeechFeatures,
    );

    final Map<String, dynamic> phenotypeVector = Map<String, dynamic>.from(
      phenotypeOutputs['phenotype_vector'] as Map,
    );

    final Map<String, dynamic> paperAlignedFeatures = Map<String, dynamic>.from(
      phenotypeOutputs['paper_aligned_features'] as Map,
    );

    final Map<String, dynamic> paperFeatureCoverage = Map<String, dynamic>.from(
      phenotypeOutputs['paper_feature_coverage'] as Map,
    );

    final List<FileSystemEntity> entities = await sessionDir.list().toList();

    final List<String> allFiles =
        entities
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .toList()
          ..sort();

    final List<String> framewiseCsvFiles = allFiles
        .where((String fileName) => fileName.endsWith('_framewise_log.csv'))
        .toList();

    final List<String> framewiseSummaryFiles = allFiles
        .where(
          (String fileName) => fileName.endsWith('_framewise_summary.json'),
        )
        .toList();

    final List<String> reactionCsvFiles = allFiles
        .where(
          (String fileName) => fileName == SessionFileNames.bubbleGameReactions,
        )
        .toList();

    final Map<String, dynamic> files = {
      SessionFileNames.childInfo: childInfo != null,
      SessionFileNames.scqResults: scqResults != null,
      SessionFileNames.stimulusProtocolSummary: stimulusProtocolSummary != null,
      SessionFileNames.stimulusEvents: stimulusEvents != null,
      SessionFileNames.videoTest: videoTest != null,
      SessionFileNames.sessionQuality: true,
      SessionFileNames.parentNameCallCues: allFiles.contains(
        SessionFileNames.parentNameCallCues,
      ),
      SessionFileNames.framewiseFaceSignals: framewiseFaceSignals != null,
      SessionFileNames.gazeCalibration: gazeCalibration != null,
      SessionFileNames.gazeCalibrationQuality: gazeCalibrationQuality != null,
      SessionFileNames.gazeCalibrationRawIris: allFiles.contains(
        SessionFileNames.gazeCalibrationRawIris,
      ),
      SessionFileNames.calibratedGazeFrames: calibratedGazeFrames != null,
      SessionFileNames.gameMetrics: gameMetrics != null,
      SessionFileNames.phenotypeVector: true,
      SessionFileNames.paperAlignedFeatures: true,
      SessionFileNames.paperFeatureCoverage: true,
      SessionFileNames.featureReliability: true,
      SessionFileNames.attentionToSpeechFeatures:
          attentionToSpeechFeatures != null,
      SessionFileNames.responseToNameFeatures: allFiles.contains(
        SessionFileNames.responseToNameFeatures,
      ),
      SessionFileNames.bubbleGameReactions: allFiles.contains(
        SessionFileNames.bubbleGameReactions,
      ),
      SessionFileNames.mlDatasetRowJson: true,
      SessionFileNames.mlDatasetRowCsv: true,
      SessionFileNames.mlDatasetSchema: true,
      SessionFileNames.prototypePrediction:
          prototypeModelPrediction['status'] == 'computed',
    };

    final Map<String, dynamic> manifest = {
      'schema_version': 'python_mobile_replica_session_manifest_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'all_files': allFiles,
      'core_files': files,
      'framewise_csv_files': framewiseCsvFiles,
      'framewise_summary_files': framewiseSummaryFiles,
      'reaction_csv_files': reactionCsvFiles,
      'counts': {
        'total_files': allFiles.length,
        'framewise_csv_count': framewiseCsvFiles.length,
        'framewise_summary_count': framewiseSummaryFiles.length,
        'reaction_csv_count': reactionCsvFiles.length,
      },
    };

    final Map<String, dynamic> finalSession = {
      'schema_version': 'python_mobile_replica_final_session_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'session_quality': sessionQuality,
      'feature_reliability': featureReliability,
      'gaze_calibration_quality': gazeCalibrationQuality,
      'calibrated_gaze_summary': {
        'status': calibratedGazeFrames?['status'],
        'frame_count': calibratedGazeFrames?['frame_count'],
        'valid_gaze_frame_count':
            calibratedGazeFrames?['valid_gaze_frame_count'],
        'valid_gaze_ratio': calibratedGazeFrames?['valid_gaze_ratio'],
        'iris_frame_count': calibratedGazeFrames?['iris_frame_count'],
        'iris_frame_ratio': calibratedGazeFrames?['iris_frame_ratio'],
        'gaze_clipping': calibratedGazeFrames?['gaze_clipping'],
      },
      'completed_modules': [
        if (childInfo != null) 'child_info',
        if (scqResults != null) 'scq',
        if (stimulusProtocolSummary != null) 'video_protocol_raw_files',
        if (videoTest != null) 'video_protocol_playback',
        if (framewiseCsvFiles.isNotEmpty) 'framewise_logs',
        if (gameMetrics != null) 'bubble_game',
        'phenotype_mapping_v1',
        'session_quality_validation',
        if (gazeCalibration != null) 'gaze_calibration',
        if (calibratedGazeFrames != null) 'calibrated_iris_gaze',
        if (attentionToSpeechFeatures != null) 'attention_to_speech_features',
        'feature_reliability_report',
        'ml_dataset_export',
        if (prototypeModelPrediction['status'] == 'computed')
          'prototype_model_prediction',
      ],
      'files': files,
      'manifest_file': SessionFileNames.sessionManifest,
      'manifest': manifest,
      'child_info': childInfo,
      'scq_results': scqResults,
      'stimulus_protocol_summary': stimulusProtocolSummary,
      'stimulus_events': stimulusEvents,
      'video_test': videoTest,
      'framewise_face_signals_summary': framewiseFaceSignals?['summary'],
      'framewise_exports': {
        'csv_files': framewiseCsvFiles,
        'summary_files': framewiseSummaryFiles,
      },
      'game_metrics': gameMetrics,
      'attention_to_speech_features': attentionToSpeechFeatures == null
          ? null
          : {
              'attention_to_speech':
                  attentionToSpeechFeatures['attention_to_speech'],
              'speech_window_count':
                  attentionToSpeechFeatures['speech_window_count'],
              'usable_speech_window_count':
                  attentionToSpeechFeatures['usable_speech_window_count'],
              'valid_speech_gaze_frame_count':
                  attentionToSpeechFeatures['valid_speech_gaze_frame_count'],
              'speech_gaze_coverage_ratio':
                  attentionToSpeechFeatures['speech_gaze_coverage_ratio'],
              'method': attentionToSpeechFeatures['method'],
            },
      'phenotype_calculation': {
        'status': 'paper_aligned_mapping_generated',
        'diagnosis_generated': false,
        'note':
            'Generated paper-aligned 23-feature phenotype vector. This is not a diagnostic classifier.',
      },
      'phenotype_vector': phenotypeVector,
      'paper_aligned_features': paperAlignedFeatures,
      'paper_feature_coverage': paperFeatureCoverage,
      'ml_dataset_export': {
        'json_file': SessionFileNames.mlDatasetRowJson,
        'csv_file': SessionFileNames.mlDatasetRowCsv,
        'schema_file': SessionFileNames.mlDatasetSchema,
        'clinical_use_allowed': mlDatasetExport['clinical_use_allowed'],
        'intended_use': mlDatasetExport['intended_use'],
      },
      'prototype_model_prediction': prototypeModelPrediction,
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.sessionManifest,
      data: manifest,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
      data: finalSession,
    );

    return finalSession;
  }
}
