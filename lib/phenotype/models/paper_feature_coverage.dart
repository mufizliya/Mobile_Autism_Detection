import 'paper_feature_names.dart';

class PaperFeatureCoverage {
  static Map<String, dynamic> build({
    required Map<String, dynamic> paperFeatures,
  }) {
    final List<String> availableFeatures = [];
    final List<String> missingFeatures = [];

    for (final String featureName in PaperFeatureNames.all) {
      final dynamic value = paperFeatures[featureName];

      if (value == null) {
        missingFeatures.add(featureName);
      } else {
        availableFeatures.add(featureName);
      }
    }

    return {
      'schema_version': 'python_mobile_replica_paper_feature_coverage_v1',
      'generated_at': DateTime.now().toIso8601String(),
      'total_expected_feature_count': PaperFeatureNames.all.length,
      'available_feature_count': availableFeatures.length,
      'missing_feature_count': missingFeatures.length,
      'available_features': availableFeatures,
      'missing_features': missingFeatures,
    };
  }
}