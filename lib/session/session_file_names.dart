class SessionFileNames {
  // Core raw session files
  static const String childInfo = 'child_info.json';
  static const String scqResults = 'scq_results.json';

  static const String videoTest = 'video_test.json';
  static const String stimulusEvents = 'stimulus_events.json';
  static const String framewiseFaceSignals = 'framewise_face_signals.json';
  static const String stimulusProtocolSummary =
      'stimulus_protocol_summary.json';
  static const String parentNameCallCues = 'parent_name_call_cues.srt';

  static const String gameMetrics = 'game_metrics.json';
  static const String bubbleGameReactions = 'bubble_game_reactions.csv';

  // Extractor output files
  static const String phenotypeVector = 'phenotype_vector.json';
  static const String paperTimeseriesFeatures =
      'paper_timeseries_features.json';
  static const String responseToNameFeatures = 'response_to_name_features.json';
  static const String attentionToSpeechFeatures =
      'attention_to_speech_features.json';
  static const String gazeSilhouetteFeatures = 'gaze_silhouette_features.json';

  // Paper mapping files
  static const String paperAlignedFeatures = 'paper_aligned_features.json';
  static const String paperFeatureMatchReport =
      'paper_feature_match_report.json';
  static const String paperFeatureCoverage = 'paper_feature_coverage.json';
  static const String featureReliability = 'feature_reliability.json';
  static const String gazeCalibrationRawIris = 'gaze_calibration_raw_iris.json';

  static const String gazeCalibration = 'gaze_calibration.json';

  static const String gazeCalibrationQuality = 'gaze_calibration_quality.json';

  // Validation/final files
  static const String sessionQuality = 'session_quality.json';
  static const String finalSession = 'final_session.json';
  static const String sessionManifest = 'session_manifest.json';

  static String framewiseLogCsv(String stimulusId) {
    return '${stimulusId}_framewise_log.csv';
  }

  static String framewiseSummaryJson(String stimulusId) {
    return '${stimulusId}_framewise_summary.json';
  }
}
