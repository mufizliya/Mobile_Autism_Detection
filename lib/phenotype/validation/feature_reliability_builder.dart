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

    final Map<String, dynamic>? framewiseFaceSignals =
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

    final Map<String, dynamic>? stimulusEvents =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.stimulusEvents,
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

    final Map<String, dynamic> qualityContext = _buildQualityContext(
      framewiseFaceSignals: framewiseFaceSignals,
      calibratedGazeFrames: calibratedGazeFrames,
      gazeCalibrationQuality: gazeCalibrationQuality,
      stimulusEvents: stimulusEvents,
      gameMetrics: gameMetrics,
    );

    final Map<String, dynamic> reliabilityByFeature = {};

    for (final String featureName in PaperFeatureNames.all) {
      final dynamic value = values[featureName];
      final String source = sources[featureName]?.toString() ?? 'unknown';

      reliabilityByFeature[featureName] = _classifyFeature(
        featureName: featureName,
        value: value,
        source: source,
        touchForceAvailable: touchForceAvailable,
        qualityContext: qualityContext,
      );
    }

    final Map<String, int> counts = {
      'computed_direct': 0,
      'computed_close_proxy': 0,
      'computed_proxy': 0,
      'missing_device_limitation': 0,
      'missing_algorithm_limitation': 0,
      'missing_data_quality': 0,
      'unknown': 0,
    };

    final Map<String, int> confidenceCounts = {
      'high': 0,
      'medium_high': 0,
      'medium': 0,
      'low': 0,
      'unknown': 0,
    };

    for (final dynamic rawItem in reliabilityByFeature.values) {
      if (rawItem is! Map) {
        counts['unknown'] = (counts['unknown'] ?? 0) + 1;
        confidenceCounts['unknown'] =
            (confidenceCounts['unknown'] ?? 0) + 1;
        continue;
      }

      final String status = rawItem['status']?.toString() ?? 'unknown';
      final String confidence = rawItem['confidence']?.toString() ?? 'unknown';

      counts[status] = (counts[status] ?? 0) + 1;
      confidenceCounts[confidence] = (confidenceCounts[confidence] ?? 0) + 1;
    }

    final Map<String, dynamic> reliability = {
      'schema_version': 'python_mobile_replica_feature_reliability_v2',
      'generated_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'paper_feature_count': PaperFeatureNames.all.length,
      'quality_context': qualityContext,
      'reliability_policy': {
        'computed_direct':
            'Feature is computed directly from the app module that generates the behavioral task data.',
        'computed_close_proxy':
            'Feature is computed from a mobile signal that closely approximates the intended paper signal and passes session quality gates.',
        'computed_proxy':
            'Feature is generated from an approximate mobile proxy. Use for exploratory alignment, not final clinical claims.',
        'missing_device_limitation':
            'Feature is missing because the current device/session cannot provide the required signal.',
        'missing_algorithm_limitation':
            'Feature is missing because the current app pipeline does not yet implement the needed algorithm.',
        'missing_data_quality':
            'Feature could theoretically be computed, but this session lacks enough usable data.',
      },
      'confidence_policy': {
        'high':
            'Strong mobile implementation for this prototype and this session passed relevant quality gates.',
        'medium_high':
            'Useful and fairly strong proxy, but still not identical to the original paper pipeline.',
        'medium':
            'Usable proxy for research prototyping, but needs algorithmic refinement or additional validation.',
        'low':
            'Weak or device-dependent proxy. Use cautiously.',
      },
      'counts': counts,
      'confidence_counts': confidenceCounts,
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

  static Map<String, dynamic> _buildQualityContext({
    required Map<String, dynamic>? framewiseFaceSignals,
    required Map<String, dynamic>? calibratedGazeFrames,
    required Map<String, dynamic>? gazeCalibrationQuality,
    required Map<String, dynamic>? stimulusEvents,
    required Map<String, dynamic>? gameMetrics,
  }) {
    final Map<String, dynamic> frameSummary =
        framewiseFaceSignals?['summary'] is Map
            ? Map<String, dynamic>.from(framewiseFaceSignals!['summary'] as Map)
            : <String, dynamic>{};

    final Map<String, dynamic> gazeClipping =
        calibratedGazeFrames?['gaze_clipping'] is Map
            ? Map<String, dynamic>.from(
                calibratedGazeFrames!['gaze_clipping'] as Map,
              )
            : <String, dynamic>{};

    final int frameCount = _intNumber(
      framewiseFaceSignals?['frame_count'] ?? frameSummary['total_frame_count'],
    );

    final double facePresenceRatio = _number(
      frameSummary['face_presence_ratio'],
    );

    final double irisPresenceRatio = _number(
      frameSummary['iris_presence_ratio'],
    );

    final double validGazeRatio = _number(
      calibratedGazeFrames?['valid_gaze_ratio'],
    );

    final double xClippedRatio = _number(gazeClipping['x_clipped_ratio']);
    final double yClippedRatio = _number(gazeClipping['y_clipped_ratio']);

    final String calibrationStatus =
        gazeCalibrationQuality?['overall_status']?.toString() ?? 'unknown';

    final dynamic rawTriggeredEvents = stimulusEvents == null
        ? null
        : stimulusEvents['triggered_name_call_events'];

    final List<dynamic> triggeredEvents = rawTriggeredEvents is List
        ? rawTriggeredEvents
        : <dynamic>[];

    final int observedNameCalls = triggeredEvents.where((dynamic item) {
      if (item is! Map) return false;
      return item['triggered'] == true &&
          item['actual_global_trigger_time_sec'] != null;
    }).length;

    final Map<String, dynamic> touchFeatures =
        gameMetrics?['touch_features'] is Map
            ? Map<String, dynamic>.from(gameMetrics!['touch_features'] as Map)
            : <String, dynamic>{};

    final bool strongFramewiseQuality =
        frameCount >= 150 && facePresenceRatio >= 0.75;

    final bool strongGazeQuality =
        calibrationStatus == 'valid' &&
        validGazeRatio >= 0.90 &&
        xClippedRatio <= 0.25 &&
        yClippedRatio <= 0.50;

    final bool strongNameCallQuality = observedNameCalls == 3;

    final bool bubbleGameCompleted =
        gameMetrics != null && _intNumber(gameMetrics['total_reactions']) > 0;

    return {
      'framewise': {
        'frame_count': frameCount,
        'face_presence_ratio': round4(facePresenceRatio),
        'iris_presence_ratio': round4(irisPresenceRatio),
        'strong_framewise_quality': strongFramewiseQuality,
      },
      'gaze': {
        'calibration_status': calibrationStatus,
        'valid_gaze_ratio': round4(validGazeRatio),
        'x_clipped_ratio': round4(xClippedRatio),
        'y_clipped_ratio': round4(yClippedRatio),
        'gaze_clipping_status': gazeClipping['status']?.toString(),
        'gaze_y_mapping_mode': calibratedGazeFrames?['gaze_y_mapping_mode'],
        'strong_gaze_quality': strongGazeQuality,
      },
      'name_call': {
        'observed_name_call_count': observedNameCalls,
        'expected_name_call_count': 3,
        'strong_name_call_quality': strongNameCallQuality,
      },
      'bubble_game': {
        'completed': bubbleGameCompleted,
        'total_reactions': _intNumber(gameMetrics?['total_reactions']),
        'score': _intNumber(gameMetrics?['score']),
        'touch_force_available': touchFeatures['touch_force_available'] == true,
      },
    };
  }

  static Map<String, dynamic> _classifyFeature({
    required String featureName,
    required dynamic value,
    required String source,
    required bool touchForceAvailable,
    required Map<String, dynamic> qualityContext,
  }) {
    final bool strongFramewiseQuality = _boolNested(
      qualityContext,
      ['framewise', 'strong_framewise_quality'],
    );

    final bool strongGazeQuality = _boolNested(
      qualityContext,
      ['gaze', 'strong_gaze_quality'],
    );

    final bool strongNameCallQuality = _boolNested(
      qualityContext,
      ['name_call', 'strong_name_call_quality'],
    );

    final bool bubbleGameCompleted = _boolNested(
      qualityContext,
      ['bubble_game', 'completed'],
    );

    if (featureName == PaperFeatureNames.popTheBubblesAverageAppliedForce) {
      if (touchForceAvailable && value != null) {
        return _result(
          status: 'computed_proxy',
          source: source,
          confidence: 'low',
          reason:
              'Touch pressure is device-dependent and should be calibrated before treating it as applied force.',
          evidence: {
            'touch_force_available': touchForceAvailable,
          },
        );
      }

      return _result(
        status: 'missing_device_limitation',
        source: source,
        confidence: 'high',
        reason:
            'This device/session did not provide usable variable touch pressure. The value is intentionally null rather than fabricated.',
        evidence: {
          'touch_force_available': touchForceAvailable,
        },
      );
    }

    if (featureName == PaperFeatureNames.popTheBubblesPoppingRate ||
        featureName == PaperFeatureNames.popTheBubblesAccuracyStd ||
        featureName == PaperFeatureNames.popTheBubblesAverageTouchLength) {
      if (value == null || !bubbleGameCompleted) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason: 'Bubble game/touch data was insufficient for this session.',
          evidence: {
            'bubble_game_completed': bubbleGameCompleted,
          },
        );
      }

      return _result(
        status: 'computed_direct',
        source: source,
        confidence: 'high',
        reason:
            'Computed directly from Flutter bubble game touch interaction logs generated by the same behavioral task.',
        evidence: {
          'bubble_game_completed': bubbleGameCompleted,
        },
      );
    }

    if (featureName == PaperFeatureNames.gazePercentSocial ||
        featureName == PaperFeatureNames.gazeSilhouetteScore) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason:
              'Calibrated iris gaze did not generate enough valid gaze-to-AOI frames for this session.',
          evidence: qualityContext['gaze'],
        );
      }

      return _result(
        status: strongGazeQuality ? 'computed_close_proxy' : 'computed_proxy',
        source: source,
        confidence: strongGazeQuality ? 'high' : 'medium',
        reason: strongGazeQuality
            ? 'Computed from calibrated MediaPipe iris landmarks using the unified native recorder. Gaze calibration, valid gaze ratio, and clipping checks passed, so this is a close mobile proxy for gaze-to-AOI features.'
            : 'Computed from calibrated MediaPipe iris landmarks, but one or more gaze quality gates did not pass. Use as a medium-confidence proxy.',
        evidence: qualityContext['gaze'],
      );
    }

    if (featureName == PaperFeatureNames.facingForwardSocialMovies ||
        featureName == PaperFeatureNames.facingForwardNonsocialMovies) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason: 'Facing-forward value is null for this session.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status:
            strongFramewiseQuality ? 'computed_close_proxy' : 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'high' : 'medium',
        reason: strongFramewiseQuality
            ? 'Computed from framewise face detection and ML Kit head-pose angles with strong frame coverage and face visibility.'
            : 'Computed from framewise face/head-pose proxy, but frame coverage or face visibility was below the stronger quality gate.',
        evidence: qualityContext['framewise'],
      );
    }

    if (featureName == PaperFeatureNames.responseToNameDelaySec ||
        featureName == PaperFeatureNames.responseToNameProportion) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason:
              'Actual name-call timing or post-call movement evidence was insufficient.',
          evidence: qualityContext['name_call'],
        );
      }

      final bool highEnough = strongFramewiseQuality && strongNameCallQuality;

      return _result(
        status: highEnough ? 'computed_close_proxy' : 'computed_proxy',
        source: source,
        confidence: highEnough ? 'medium_high' : 'medium',
        reason: highEnough
            ? 'Computed from actual playback-time name-call triggers and post-call head movement evidence. All expected name-call cues were observed, but this still uses a head-movement response proxy until gaze-shift response logic is added.'
            : 'Computed from name-call/head-movement proxy, but name-call timing or framewise quality gates were not fully strong.',
        evidence: {
          'framewise': qualityContext['framewise'],
          'name_call': qualityContext['name_call'],
        },
      );
    }

    if (featureName == PaperFeatureNames.attentionToSpeech) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason: 'Attention-to-speech value is null for this session.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status:
            strongFramewiseQuality ? 'computed_proxy' : 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'medium' : 'low',
        reason:
            'Current implementation uses facing-forward ratio during speech/social stimuli. This remains a proxy until speaker-window plus calibrated gaze-to-speaking-AOI logic is implemented.',
        evidence: qualityContext['framewise'],
      );
    }

    if (featureName == PaperFeatureNames.blinkRateSocialMovies ||
        featureName == PaperFeatureNames.blinkRateNonsocialMovies) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason:
              'Eye-open probability signal was insufficient for blink-rate estimation.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status: 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'medium_high' : 'medium',
        reason:
            'Computed from ML Kit eye-open probability transitions. Useful mobile proxy, but not upgraded to high until explicit blink-event duration filtering is added.',
        evidence: qualityContext['framewise'],
      );
    }

    if (featureName == PaperFeatureNames.headMovementSocialMovies ||
        featureName == PaperFeatureNames.headMovementNonsocialMovies ||
        featureName == PaperFeatureNames.headMovementComplexitySocialMovies ||
        featureName == PaperFeatureNames.headMovementComplexityNonsocialMovies ||
        featureName == PaperFeatureNames.headMovementAccelerationSocialMovies ||
        featureName ==
            PaperFeatureNames.headMovementAccelerationNonsocialMovies) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason: 'Head movement value is null for this session.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status:
            strongFramewiseQuality ? 'computed_proxy' : 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'medium_high' : 'medium',
        reason:
            'Computed from framewise mobile head/face motion signals. Confidence is improved by strong framewise quality, but this remains below high until Patch 2 switches movement computation fully to yaw/pitch/roll angular dynamics.',
        evidence: qualityContext['framewise'],
      );
    }

    if (featureName == PaperFeatureNames.mouthComplexitySocialMovies ||
        featureName == PaperFeatureNames.mouthComplexityNonsocialMovies) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason:
              'Mouth contour feature could not be computed for this session.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status:
            strongFramewiseQuality ? 'computed_close_proxy' : 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'medium_high' : 'medium',
        reason:
            'Computed from normalized ML Kit lip-contour mouth-open signal. It is a close mobile proxy when framewise quality is strong, but not the original paper facial-landmark implementation.',
        evidence: qualityContext['framewise'],
      );
    }

    if (featureName == PaperFeatureNames.eyebrowComplexitySocialMovies ||
        featureName == PaperFeatureNames.eyebrowComplexityNonsocialMovies) {
      if (value == null) {
        return _result(
          status: 'missing_data_quality',
          source: source,
          confidence: 'medium',
          reason:
              'Eyebrow contour signal was not available or not stable in this session.',
          evidence: qualityContext['framewise'],
        );
      }

      return _result(
        status:
            strongFramewiseQuality ? 'computed_close_proxy' : 'computed_proxy',
        source: source,
        confidence: strongFramewiseQuality ? 'medium_high' : 'medium',
        reason:
            'Computed from normalized ML Kit eyebrow-to-eye contour signal. It is a close mobile proxy when framewise quality is strong, but not the original paper facial-landmark implementation.',
        evidence: qualityContext['framewise'],
      );
    }

    if (value == null) {
      return _result(
        status: 'missing_data_quality',
        source: source,
        confidence: 'medium',
        reason: 'Feature value is null for this session.',
      );
    }

    return _result(
      status: 'computed_proxy',
      source: source,
      confidence: 'medium',
      reason: 'Computed from mobile proxy signals.',
    );
  }

  static Map<String, dynamic> _result({
    required String status,
    required String source,
    required String confidence,
    required String reason,
    dynamic evidence,
  }) {
    return {
      'status': status,
      'source': source,
      'confidence': confidence,
      'reason': reason,
      'evidence': ?evidence,
    };
  }

  static String _overallReliability(Map<String, int> counts) {
    final int algorithmMissing = counts['missing_algorithm_limitation'] ?? 0;
    final int deviceMissing = counts['missing_device_limitation'] ?? 0;
    final int dataMissing = counts['missing_data_quality'] ?? 0;
    final int closeProxy = counts['computed_close_proxy'] ?? 0;
    final int direct = counts['computed_direct'] ?? 0;

    final int missing = algorithmMissing + deviceMissing + dataMissing;

    if (missing == 0 && closeProxy + direct >= 18) {
      return 'strong_mobile_research_reliability_all_features_available';
    }

    if (missing <= 1 && closeProxy + direct >= 10) {
      return 'strong_mobile_research_reliability_with_known_limitations';
    }

    if (missing <= 3) {
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
        'area': 'head_pose_dynamics',
        'features': [
          PaperFeatureNames.headMovementSocialMovies,
          PaperFeatureNames.headMovementNonsocialMovies,
          PaperFeatureNames.headMovementComplexitySocialMovies,
          PaperFeatureNames.headMovementComplexityNonsocialMovies,
          PaperFeatureNames.headMovementAccelerationSocialMovies,
          PaperFeatureNames.headMovementAccelerationNonsocialMovies,
        ],
        'recommendation':
            'Patch 2: compute head movement from yaw/pitch/roll angular dynamics instead of face-center motion.',
      },
      {
        'priority': 2,
        'area': 'blink_event_detection',
        'features': [
          PaperFeatureNames.blinkRateSocialMovies,
          PaperFeatureNames.blinkRateNonsocialMovies,
        ],
        'recommendation':
            'Patch 3: detect blink events using eye-open probability thresholds and valid blink-duration windows.',
      },
      {
        'priority': 3,
        'area': 'response_to_name_gaze_plus_head',
        'features': [
          PaperFeatureNames.responseToNameDelaySec,
          PaperFeatureNames.responseToNameProportion,
        ],
        'recommendation':
            'Patch 4: combine post-call head movement, gaze shift, and face reorientation for response-to-name detection.',
      },
      {
        'priority': 4,
        'area': 'clinical_model_training',
        'features': PaperFeatureNames.all,
        'recommendation':
            'Do not generate diagnosis until a trained and validated model is available for these mobile-derived feature distributions.',
      },
    ];

    if (!touchForceAvailable) {
      improvements.add({
        'priority': 5,
        'area': 'touch_force_device_support',
        'features': [PaperFeatureNames.popTheBubblesAverageAppliedForce],
        'recommendation':
            'Use a device with variable pressure support or keep this feature as a documented device limitation. Do not fabricate force values.',
      });
    }

    return improvements;
  }

  static bool _boolNested(Map<String, dynamic> map, List<String> keys) {
    dynamic current = map;

    for (final String key in keys) {
      if (current is! Map) return false;
      current = current[key];
    }

    return current == true;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _intNumber(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }
}
