import 'dart:io';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import 'prototype_xgboost_runtime.dart';

class PrototypeModelPredictionService {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final Map<String, dynamic> payload = await _build(sessionDir: sessionDir);

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.prototypePrediction,
      data: payload,
    );

    return payload;
  }

  static Future<Map<String, dynamic>> _build({
    required Directory sessionDir,
  }) async {
    try {
      final Map<String, dynamic>? mlDataset =
          await SessionService.readJsonIfExists(
        sessionDir: sessionDir,
        fileName: SessionFileNames.mlDatasetRowJson,
      );

      if (mlDataset == null) {
        return _errorPayload(
          status: 'missing_ml_dataset_row',
          message: 'ml_dataset_row.json was not found for this session.',
        );
      }

      final Map<String, dynamic> row = mlDataset['row'] is Map
          ? Map<String, dynamic>.from(mlDataset['row'] as Map)
          : Map<String, dynamic>.from(mlDataset);

      final PrototypeXgboostRuntime runtime = await PrototypeXgboostRuntime.load();
      final PrototypeXgboostPrediction prediction = runtime.predict(row);

      return <String, dynamic>{
        'schema_version': 'mobile_prototype_model_prediction_v1',
        'generated_at': DateTime.now().toIso8601String(),
        'status': 'computed',
        'asset_path': PrototypeXgboostRuntime.defaultAssetPath,
        'session_id': row['session_id'],
        'dataset_row_schema_version': row['schema_version'],
        ...prediction.toJson(),
        'display_warning':
            'Prototype model result for testing only. Not a diagnosis, not a clinical screen, and not for medical decisions.',
      };
    } catch (error) {
      return _errorPayload(
        status: 'prediction_failed',
        message: error.toString(),
      );
    }
  }

  static Map<String, dynamic> _errorPayload({
    required String status,
    required String message,
  }) {
    return <String, dynamic>{
      'schema_version': 'mobile_prototype_model_prediction_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'status': status,
      'clinical_use_allowed': false,
      'prototype_prediction': 'unavailable',
      'autism_probability_prototype': null,
      'threshold': null,
      'error': message,
      'display_warning':
          'Prototype model result unavailable. This app is still research-only and not diagnostic.',
    };
  }
}
