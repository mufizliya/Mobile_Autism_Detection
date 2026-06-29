import 'dart:io';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../models/paper_feature_names.dart';

class FeatureReliabilityBuilder {
  static Future<Map<String, dynamic>> buildAndSave({
    required Directory sessionDir,
  }) async {
    final Map<String, dynamic>? paperAlignedFeatures =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.paperAlignedFeatures,
        );

    final Map<String, dynamic>? gameMetrics =
        await SessionService.readJsonIfExists(
          sessionDir: sessionDir,
          fileName: SessionFileNames.gameMetrics,
        );

    final Map<String, dynamic> values = paperAlignedFeatures?['values'] is Map
        ? Map<String, dynamic>.from(paperAlignedFeatures!['values'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> sources = paperAlignedFeatures?['sources'] is Map
        ? Map<String, dynamic>.from(paperAlignedFeatures!['sources'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> touchFeatures =
        gameMetrics?['touch_features'] is Map
        ? Map<String, dynamic>.from(gameMetrics!['touch_features'] as Map)
        : <String, dynamic>{};

    final bool touchForceAvailable =
        touchFeatures['touch_force_available'] == true;

    final Map<String, dynamic> reliabilityByFeature = {};

    for (final String featureName in PaperFeatureNames.all) {
      final dynamic value = values[featureName];
      final String source = sources[featureName]?.toString() ?? 'unknown';

      reliabilityByFeature[featureName] = _classifyFeature(
        featureName: featureName,
        value: value,
        source: source,
        touchForceAvailable: touchForceAvailable,
      );
    }

    final Map<String, int> counts = {
      'computed_direct': 0,
      'computed_proxy': 0,
      'missing_device_limitation': 0,
      'missing_algorithm_limitation': 0,
      'missing_data_quality': 0,
      'unknown': 0,
    };

    for (final dynamic rawItem in reliabilityByFeature.values) {
      if (rawItem is! Map) {
        counts['unknown'] = (counts['unknown'] ?? 0) + 1;
        continue;
      }

      final String status = rawItem['status']?.toString() ?? 'unknown';

      counts[status] = (counts[status] ?? 0) + 1;
    }

    final Map<String, dynamic> reliability = {
      'schema_version': 'python_mobile_replica_feature_reliability_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'paper_feature_count': PaperFeatureNames.all.length,
      'reliability_policy': {
        'computed_direct':
            'Feature is computed from a signal close to the intended measurement.',
        'computed_proxy':
            'Feature is generated from an approximate mobile proxy. Use for exploratory alignment, not final clinical claims.',
        'missing_device_limitation':
            'Feature is missing because the current device/session cannot provide the required signal.',
        'missing_algorithm_limitation':
            'Feature is missing because the current app pipeline does not yet implement the needed algorithm.',
        'missing_data_quality':
            'Feature could theoretically be computed, but this session lacks enough usable data.',
      },
      'counts': counts,
      'features': reliabilityByFeature,
      'overall_reliability': _overallReliability(counts),
      'recommended_next_improvements': _recommendedNextImprovements(
        touchForceAvailable: touchForceAvailable,
      ),
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.featureReliability,
      data: reliability,
    );

    return reliability;
  }

  static Map<String, dynamic> _classifyFeature({
    required String featureName,
    required dynamic value,
    required String source,
    required bool touchForceAvailable,
  }) {
    if (featureName == PaperFeatureNames.popTheBubblesAverageAppliedForce) {
      if (touchForceAvailable && value != null) {
        return {
          'status': 'computed_proxy',
          'source': source,
          'confidence': 'low',
          'reason':
              'Touch pressure is device-dependent and should be calibrated before treating it as applied force.',
        };
      }

      return {
        'status': 'missing_device_limitation',
        'source': source,
        'confidence': 'high',
        'reason':
            'This device/session did not provide usable variable touch pressure.',
      };
    }

    if (featureName == PaperFeatureNames.gazePercentSocial ||
        featureName == PaperFeatureNames.gazeSilhouetteScore) {
      if (value == null) {
        return {
          'status': 'missing_algorithm_limitation',
          'source': source,
          'confidence': 'high',
          'reason':
              'Calibrated iris gaze could not generate enough valid gaze-to-AOI frames for this session.',
        };
      }

      return {
        'status': 'computed_proxy',
        'source': source,
        'confidence': 'medium',
        'reason':
            'Computed using calibrated MediaPipe iris landmarks mapped to screen AOIs. This is closer to gaze estimation than head-pose proxy, but not clinical eye-tracking hardware.',
      };
    }

    if (featureName == PaperFeatureNames.eyebrowComplexitySocialMovies ||
        featureName == PaperFeatureNames.eyebrowComplexityNonsocialMovies) {
      if (value == null) {
        return {
          'status': 'missing_algorithm_limitation',
          'source': source,
          'confidence': 'medium',
          'reason':
              'Eyebrow contour signal was not available or not stable in this session.',
        };
      }

      return {
        'status': 'computed_proxy',
        'source': source,
        'confidence': 'medium',
        'reason':
            'Computed from ML Kit eyebrow contour proxy, not the original paper facial landmark pipeline.',
      };
    }

    if (featureName == PaperFeatureNames.mouthComplexitySocialMovies ||
        featureName == PaperFeatureNames.mouthComplexityNonsocialMovies) {
      if (value == null) {
        return {
          'status': 'missing_data_quality',
          'source': source,
          'confidence': 'medium',
          'reason':
              'Mouth contour feature could not be computed for this session.',
        };
      }

      return {
        'status': 'computed_proxy',
        'source': source,
        'confidence': 'medium',
        'reason':
            'Computed from ML Kit mouth contour proxy, not the original paper facial landmark pipeline.',
      };
    }

    if (featureName == PaperFeatureNames.responseToNameDelaySec ||
        featureName == PaperFeatureNames.responseToNameProportion) {
      if (value == null) {
        return {
          'status': 'missing_data_quality',
          'source': source,
          'confidence': 'medium',
          'reason':
              'Actual name-call timing or post-call movement evidence was insufficient.',
        };
      }

      return {
        'status': 'computed_proxy',
        'source': source,
        'confidence': 'medium',
        'reason':
            'Computed from actual playback-time name-call events and head movement proxy.',
      };
    }

    if (featureName == PaperFeatureNames.popTheBubblesPoppingRate ||
        featureName == PaperFeatureNames.popTheBubblesAccuracyStd ||
        featureName == PaperFeatureNames.popTheBubblesAverageTouchLength) {
      if (value == null) {
        return {
          'status': 'missing_data_quality',
          'source': source,
          'confidence': 'medium',
          'reason': 'Bubble game/touch data was insufficient for this session.',
        };
      }

      return {
        'status': 'computed_direct',
        'source': source,
        'confidence': 'medium',
        'reason':
            'Computed directly from Flutter bubble game touch interaction logs.',
      };
    }

    if (value == null) {
      return {
        'status': 'missing_data_quality',
        'source': source,
        'confidence': 'medium',
        'reason': 'Feature value is null for this session.',
      };
    }

    return {
      'status': 'computed_proxy',
      'source': source,
      'confidence': 'medium',
      'reason': 'Computed from mobile face/head/eye proxy signals.',
    };
  }

  static String _overallReliability(Map<String, int> counts) {
    final int algorithmMissing = counts['missing_algorithm_limitation'] ?? 0;

    final int deviceMissing = counts['missing_device_limitation'] ?? 0;

    final int dataMissing = counts['missing_data_quality'] ?? 0;

    final int lowQualityMissing =
        algorithmMissing + deviceMissing + dataMissing;

    if (lowQualityMissing == 0) {
      return 'all_features_available_with_mixed_direct_and_proxy_reliability';
    }

    if (lowQualityMissing <= 3) {
      return 'mostly_available_with_known_limitations';
    }

    return 'limited_reliability_repeat_or_improve_pipeline';
  }

  static List<Map<String, dynamic>> _recommendedNextImprovements({
    required bool touchForceAvailable,
  }) {
    final List<Map<String, dynamic>> improvements = [
      {
        'priority': 1,
        'area': 'true_gaze_to_aoi',
        'features': [
          PaperFeatureNames.gazePercentSocial,
          PaperFeatureNames.gazeSilhouetteScore,
        ],
        'recommendation':
            'Improve calibrated iris gaze by validating against known screen targets and adding stronger calibration/modeling.',
      },
      {
        'priority': 2,
        'area': 'clinical_model_training',
        'features': PaperFeatureNames.all,
        'recommendation':
            'Do not generate diagnosis until a trained and validated model is available for these mobile-derived feature distributions.',
      },
    ];

    if (!touchForceAvailable) {
      improvements.add({
        'priority': 3,
        'area': 'touch_force_device_support',
        'features': [PaperFeatureNames.popTheBubblesAverageAppliedForce],
        'recommendation':
            'Use a device with variable pressure support or calibrate pressure/radius proxy across supported Android devices.',
      });
    }

    return improvements;
  }
}
