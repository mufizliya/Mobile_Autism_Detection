import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class PrototypeXgboostPrediction {
  const PrototypeXgboostPrediction({
    required this.probability,
    required this.threshold,
    required this.predictedLabel,
    required this.modelId,
    required this.targetMode,
    required this.featureCount,
    required this.missingFeatureCount,
    required this.validation,
    required this.warning,
    required this.explanation,
  });

  final double probability;
  final double threshold;
  final String predictedLabel;
  final String modelId;
  final String targetMode;
  final int featureCount;
  final int missingFeatureCount;
  final Map<String, dynamic> validation;
  final String warning;
  final Map<String, dynamic> explanation;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'autism_probability_prototype': probability,
      'threshold': threshold,
      'prototype_prediction': predictedLabel,
      'model_id': modelId,
      'target_mode': targetMode,
      'feature_count': featureCount,
      'missing_feature_count': missingFeatureCount,
      'clinical_use_allowed': false,
      'validation': validation,
      'prototype_explanation': explanation,
      'warning': warning,
    };
  }
}

class PrototypeXgboostRuntime {
  PrototypeXgboostRuntime._(this._model);

  final Map<String, dynamic> _model;

  static const String defaultAssetPath =
      'assets/model/prototype_xgboost_model.json';

  static PrototypeXgboostRuntime? _cached;

  static Future<PrototypeXgboostRuntime> load({
    String assetPath = defaultAssetPath,
  }) async {
    if (_cached != null) {
      return _cached!;
    }

    final String raw = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> model = Map<String, dynamic>.from(
      jsonDecode(raw) as Map,
    );
    _cached = PrototypeXgboostRuntime._(model);
    return _cached!;
  }

  PrototypeXgboostPrediction predict(Map<String, dynamic> row) {
    final List<String> featureOrder = _featureOrder;
    final double threshold = _number(_model['threshold']) ?? 0.5;
    final double baseMargin = _number(_model['base_margin']) ?? 0.0;
    final double missingSentinel = _number(_model['missing_sentinel']) ?? -999.0;
    final List<dynamic> trees = _model['trees'] is List
        ? _model['trees'] as List<dynamic>
        : <dynamic>[];

    int missingFeatureCount = 0;
    final Map<String, double> features = <String, double>{};
    final Map<String, double?> originalFeatureValues = <String, double?>{};

    for (final String feature in featureOrder) {
      final double? value = _number(row[feature]);
      final bool isMissing = value == null || value == missingSentinel;
      originalFeatureValues[feature] = isMissing ? null : value;
      if (isMissing) {
        missingFeatureCount += 1;
        features[feature] = missingSentinel;
      } else {
        features[feature] = value;
      }
    }

    double margin = baseMargin;
    for (final dynamic tree in trees) {
      if (tree is Map) {
        margin += _evalNode(
          Map<String, dynamic>.from(tree),
          features,
          missingSentinel,
        );
      }
    }

    final double probability = _sigmoid(margin);
    final String predictedLabel = probability >= threshold
        ? 'autism_positive'
        : 'autism_negative';

    return PrototypeXgboostPrediction(
      probability: probability,
      threshold: threshold,
      predictedLabel: predictedLabel,
      modelId: _model['model_id']?.toString() ?? 'unknown_model',
      targetMode: _model['target_mode']?.toString() ?? 'autism_vs_nonautism',
      featureCount: featureOrder.length,
      missingFeatureCount: missingFeatureCount,
      validation: _model['validation'] is Map
          ? Map<String, dynamic>.from(_model['validation'] as Map)
          : <String, dynamic>{},
      warning: _model['warning']?.toString() ??
          'Research prototype only. Not validated for clinical or diagnostic use.',
      explanation: _buildExplanation(
        originalFeatureValues: originalFeatureValues,
        missingFeatureCount: missingFeatureCount,
      ),
    );
  }

  List<String> get _featureOrder {
    final dynamic raw = _model['feature_order'];
    if (raw is List) {
      return raw.map((dynamic item) => item.toString()).toList();
    }
    return <String>[];
  }

  Map<String, dynamic> _buildExplanation({
    required Map<String, double?> originalFeatureValues,
    required int missingFeatureCount,
  }) {
    final dynamic rawProfile = _model['explanation_profile'];
    if (rawProfile is! Map) {
      return <String, dynamic>{
        'status': 'unavailable',
        'reason': 'model asset does not contain explanation_profile',
        'method': 'not_available',
        'top_contributors': <Map<String, dynamic>>[],
      };
    }

    final Map<String, dynamic> profile = Map<String, dynamic>.from(rawProfile);
    final List<dynamic> rawFeatures = profile['features'] is List
        ? profile['features'] as List<dynamic>
        : <dynamic>[];

    final List<Map<String, dynamic>> contributors = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> missingImportantFeatures = <Map<String, dynamic>>[];

    for (final dynamic item in rawFeatures) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> meta = Map<String, dynamic>.from(item);
      final String feature = meta['feature']?.toString() ?? '';
      if (feature.isEmpty) {
        continue;
      }

      final double? value = originalFeatureValues[feature];
      final double importance = _number(meta['importance_normalized']) ?? 0.0;
      final String displayName = meta['display_name']?.toString() ?? feature;
      final String unit = meta['unit']?.toString() ?? '';

      if (value == null) {
        if (importance > 0) {
          missingImportantFeatures.add(<String, dynamic>{
            'feature': feature,
            'display_name': displayName,
            'importance_normalized': importance,
            'message': 'Feature was unavailable for this session.',
          });
        }
        continue;
      }

      final double? autismMedian = _number(meta['autism_median']);
      final double? nonAutismMedian = _number(meta['nonautism_median']);
      if (autismMedian == null || nonAutismMedian == null) {
        continue;
      }

      final double delta = autismMedian - nonAutismMedian;
      if (delta.abs() < 1e-9) {
        continue;
      }

      final double midpoint = (autismMedian + nonAutismMedian) / 2.0;
      final bool higherMeansAutismPattern = delta > 0;
      final bool valueOnAutismSide = higherMeansAutismPattern
          ? value >= midpoint
          : value <= midpoint;

      final double halfGap = math.max(delta.abs() / 2.0, 1e-9);
      final double normalizedDistance = ((value - midpoint).abs() / halfGap)
          .clamp(0.0, 2.5)
          .toDouble();
      final double strength = (importance * normalizedDistance)
          .clamp(0.0, double.infinity)
          .toDouble();

      if (strength <= 0) {
        continue;
      }

      final String evidenceDirection = valueOnAutismSide
          ? 'toward_autism_pattern'
          : 'toward_nonautism_pattern';
      final String relativeDirection = value >= midpoint ? 'higher' : 'lower';
      final String autismDirection = higherMeansAutismPattern
          ? 'higher_values_match_synthetic_autism_reference'
          : 'lower_values_match_synthetic_autism_reference';

      contributors.add(<String, dynamic>{
        'feature': feature,
        'display_name': displayName,
        'unit': unit,
        'value': value,
        'nonautism_reference_median': nonAutismMedian,
        'autism_reference_median': autismMedian,
        'reference_midpoint': midpoint,
        'importance_normalized': importance,
        'normalized_distance_from_midpoint': normalizedDistance,
        'prototype_evidence_strength': strength,
        'evidence_direction': evidenceDirection,
        'relative_direction': relativeDirection,
        'autism_reference_direction': autismDirection,
        'message': _contributionMessage(
          displayName: displayName,
          valueOnAutismSide: valueOnAutismSide,
          relativeDirection: relativeDirection,
        ),
      });
    }

    contributors.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final double av = _number(a['prototype_evidence_strength']) ?? 0.0;
      final double bv = _number(b['prototype_evidence_strength']) ?? 0.0;
      return bv.compareTo(av);
    });

    missingImportantFeatures.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final double av = _number(a['importance_normalized']) ?? 0.0;
      final double bv = _number(b['importance_normalized']) ?? 0.0;
      return bv.compareTo(av);
    });

    return <String, dynamic>{
      'status': contributors.isEmpty ? 'no_available_contributors' : 'computed',
      'method': 'reference_median_direction_weighted_by_training_importance',
      'note': 'Approximate prototype explanation only. It is not SHAP and not clinical evidence.',
      'reference_source': profile['reference_source']?.toString() ?? 'unknown',
      'top_contributors': contributors.take(6).toList(),
      'missing_important_features': missingImportantFeatures.take(5).toList(),
      'missing_feature_count': missingFeatureCount,
    };
  }

  static String _contributionMessage({
    required String displayName,
    required bool valueOnAutismSide,
    required String relativeDirection,
  }) {
    final String side = valueOnAutismSide
        ? 'toward the synthetic autism-positive pattern'
        : 'toward the synthetic non-autism pattern';
    return '$displayName was $relativeDirection than the synthetic reference midpoint, so this prototype explanation places it $side.';
  }

  double _evalNode(
    Map<String, dynamic> node,
    Map<String, double> features,
    double missingSentinel,
  ) {
    final double? leaf = _number(node['leaf']);
    if (leaf != null) {
      return leaf;
    }

    final String split = node['split']?.toString() ?? '';
    final double splitCondition = _number(node['split_condition']) ?? 0.0;
    final double value = features[split] ?? missingSentinel;

    // The Python training pipeline encodes missing features as the numeric
    // sentinel -999. So the mobile runtime treats the sentinel as a real value
    // for tree traversal, matching the training data matrix.
    final int targetNodeId = value < splitCondition
        ? (_int(node['yes']) ?? -1)
        : (_int(node['no']) ?? -1);

    final List<dynamic> children = node['children'] is List
        ? node['children'] as List<dynamic>
        : <dynamic>[];

    for (final dynamic child in children) {
      if (child is! Map) {
        continue;
      }
      final Map<String, dynamic> childMap = Map<String, dynamic>.from(child);
      if ((_int(childMap['nodeid']) ?? -2) == targetNodeId) {
        return _evalNode(childMap, features, missingSentinel);
      }
    }

    return 0.0;
  }

  static double _sigmoid(double value) {
    if (value >= 0) {
      final double z = math.exp(-value);
      return 1.0 / (1.0 + z);
    }
    final double z = math.exp(value);
    return z / (1.0 + z);
  }

  static double? _number(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      if (parsed.isFinite) {
        return parsed;
      }
      return null;
    }
    final double? parsed = double.tryParse(value.toString());
    if (parsed == null || !parsed.isFinite) {
      return null;
    }
    return parsed;
  }

  static int? _int(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}
