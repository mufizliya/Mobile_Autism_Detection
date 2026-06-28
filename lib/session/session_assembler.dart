import 'dart:io';

import 'session_file_names.dart';
import 'session_service.dart';
import '../phenotype/mappers/paper_phenotype_mapper.dart';

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

    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gameMetrics,
        );
    final Map<String, dynamic> phenotypeOutputs =
        await PaperPhenotypeMapper.buildAndSave(sessionDir: sessionDir);

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
      SessionFileNames.parentNameCallCues: allFiles.contains(
        SessionFileNames.parentNameCallCues,
      ),
      SessionFileNames.framewiseFaceSignals: framewiseFaceSignals != null,
      SessionFileNames.gameMetrics: gameMetrics != null,
      SessionFileNames.phenotypeVector: true,
      SessionFileNames.paperAlignedFeatures: true,
      SessionFileNames.paperFeatureCoverage: true,
      SessionFileNames.bubbleGameReactions: allFiles.contains(
        SessionFileNames.bubbleGameReactions,
      ),
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
      'completed_modules': [
        if (childInfo != null) 'child_info',
        if (scqResults != null) 'scq',
        if (stimulusProtocolSummary != null) 'video_protocol_raw_files',
        if (videoTest != null) 'video_protocol_playback',
        if (framewiseCsvFiles.isNotEmpty) 'framewise_logs',
        if (gameMetrics != null) 'bubble_game',
        'phenotype_mapping_v1',
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
      'phenotype_calculation': {
        'status': 'paper_aligned_mapping_generated',
        'diagnosis_generated': false,
        'note':
            'Generated paper-aligned 23-feature phenotype vector. This is not a diagnostic classifier.',
      },
      'phenotype_vector': phenotypeVector,
      'paper_aligned_features': paperAlignedFeatures,
      'paper_feature_coverage': paperFeatureCoverage,
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
