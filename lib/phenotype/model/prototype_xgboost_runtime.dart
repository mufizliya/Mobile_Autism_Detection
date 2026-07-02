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
    for (final String feature in featureOrder) {
      final double? value = _number(row[feature]);
      if (value == null) {
        missingFeatureCount += 1;
        features[feature] = missingSentinel;
      } else {
        features[feature] = value;
      }
    }

    double margin = baseMargin;
    for (final dynamic tree in trees) {
      if (tree is Map) {
        margin += _evalNode(Map<String, dynamic>.from(tree), features, missingSentinel);
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
    );
  }

  List<String> get _featureOrder {
    final dynamic raw = _model['feature_order'];
    if (raw is List) {
      return raw.map((dynamic item) => item.toString()).toList();
    }
    return <String>[];
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
