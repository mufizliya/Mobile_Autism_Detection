import 'dart:convert';

import 'package:flutter/services.dart';

class StimulusProtocolService {
  static const String scheduleAssetPath =
      'assets/stimuli/stimulus_schedule.json';

  static const String masterTimelineAssetPath =
      'assets/stimuli/master/stimulus_master_timeline.json';

  static const String masterVideoAssetPath =
      'assets/stimuli/master/stimulus_master_protocol_cued.mp4';

  static Future<Map<String, dynamic>> loadSchedule() async {
    final String raw = await rootBundle.loadString(scheduleAssetPath);

    final dynamic decoded = jsonDecode(raw);

    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Map<String, dynamic>> loadMasterTimeline() async {
    final String raw = await rootBundle.loadString(masterTimelineAssetPath);

    final dynamic decoded = jsonDecode(raw);

    return Map<String, dynamic>.from(decoded as Map);
  }

  static List<Map<String, dynamic>> getAllStimuli(
    Map<String, dynamic> schedule,
  ) {
    final dynamic rawStimuli = schedule['stimuli'];

    if (rawStimuli is! List) {
      return [];
    }

    return rawStimuli
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static List<Map<String, dynamic>> getVideoStimuli(
    Map<String, dynamic> schedule,
  ) {
    return getAllStimuli(schedule).where(
      (Map<String, dynamic> stimulus) {
        return stimulus['type'] != 'name_call_event';
      },
    ).toList();
  }

  static List<Map<String, dynamic>> getNameCallEvents(
    Map<String, dynamic> schedule,
  ) {
    return getAllStimuli(schedule).where(
      (Map<String, dynamic> stimulus) {
        return stimulus['type'] == 'name_call_event';
      },
    ).toList();
  }

  static String formatSrtTime(
    double seconds,
  ) {
    final int hours = seconds ~/ 3600;
    final double remainingAfterHours = seconds % 3600;

    final int minutes = remainingAfterHours ~/ 60;
    final double remainingSeconds = remainingAfterHours % 60;

    final int wholeSeconds = remainingSeconds.floor();
    final int milliseconds = ((remainingSeconds - wholeSeconds) * 1000).round();

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${wholeSeconds.toString().padLeft(2, '0')},'
        '${milliseconds.toString().padLeft(3, '0')}';
  }

  static String buildParentCueSrt({
    required List<Map<String, dynamic>> timeline,
    required String childName,
  }) {
    final StringBuffer buffer = StringBuffer();
    int cueIndex = 1;

    for (final Map<String, dynamic> item in timeline) {
      final dynamic rawEvents = item['scheduled_name_call_events'];

      if (rawEvents is! List) {
        continue;
      }

      for (final dynamic rawEvent in rawEvents) {
        if (rawEvent is! Map) {
          continue;
        }

        final Map<String, dynamic> event = Map<String, dynamic>.from(rawEvent);

        final double startTime = _toDouble(
          event['global_call_time_sec'],
        );

        final double endTime = startTime + 1.5;

        final String text = childName.trim().isNotEmpty
            ? 'PARENT: CALL ${childName.trim()} NOW'
            : 'PARENT: CALL CHILD NAME NOW';

        buffer.writeln(cueIndex);
        buffer.writeln(
          '${formatSrtTime(startTime)} --> ${formatSrtTime(endTime)}',
        );
        buffer.writeln(text);
        buffer.writeln();

        cueIndex += 1;
      }
    }

    return buffer.toString();
  }

  static List<Map<String, dynamic>> collectScheduledNameCallEvents(
    List<Map<String, dynamic>> timeline,
  ) {
    final List<Map<String, dynamic>> events = [];

    for (final Map<String, dynamic> item in timeline) {
      final String stimulusId = item['stimulus_id']?.toString() ?? '';

      final dynamic rawEvents = item['scheduled_name_call_events'];

      if (rawEvents is! List) {
        continue;
      }

      for (final dynamic rawEvent in rawEvents) {
        if (rawEvent is! Map) {
          continue;
        }

        final Map<String, dynamic> event = Map<String, dynamic>.from(rawEvent);

        event['stimulus_id'] = stimulusId;

        events.add(event);
      }
    }

    return events;
  }

  static List<Map<String, dynamic>> buildTriggeredNameCallEvents(
    List<Map<String, dynamic>> scheduledEvents,
  ) {
    return scheduledEvents.map(
      (Map<String, dynamic> event) {
        final Map<String, dynamic> triggered = Map<String, dynamic>.from(event);

        final double globalCallTime = _toDouble(
          triggered['global_call_time_sec'],
        );

        final double localCallTime = _toDouble(
          triggered['call_time_sec'],
        );

        triggered['triggered'] = true;
        triggered['actual_global_trigger_time_sec'] =
            double.parse(globalCallTime.toStringAsFixed(4));
        triggered['actual_trigger_time_sec'] =
            double.parse(localCallTime.toStringAsFixed(4));
        triggered['actual_wall_time'] = DateTime.now().millisecondsSinceEpoch /
            1000.0;

        return triggered;
      },
    ).toList();
  }

  static Map<String, dynamic> buildVideoTestSkeleton({
    required Map<String, dynamic> schedule,
    required Map<String, dynamic> masterTimeline,
    required List<Map<String, dynamic>> triggeredEvents,
  }) {
    final List<Map<String, dynamic>> timeline =
        _timelineFromMaster(masterTimeline);

    final List<Map<String, dynamic>> stimulusResults = [];

    for (final Map<String, dynamic> item in timeline) {
      final String stimulusId = item['stimulus_id']?.toString() ?? '';

      final List<Map<String, dynamic>> triggeredForStimulus =
          triggeredEvents.where(
        (Map<String, dynamic> event) {
          return event['stimulus_id'] == stimulusId;
        },
      ).toList();

      stimulusResults.add({
        'stimulus': item['stimulus'] ?? <String, dynamic>{},
        'video_metrics': {
          'stimulus_id': stimulusId,
          'video_path': item['video_path'],
          'played': true,
          'master_video_path': masterVideoAssetPath,
          'global_start_sec': item['global_start_sec'],
          'global_end_sec': item['global_end_sec'],
          'clip_start_sec': item['clip_start_sec'],
          'clip_end_sec': item['clip_end_sec'],
          'clip_duration_sec': item['clip_duration_sec'],
          'scheduled_name_call_events':
              item['scheduled_name_call_events'] ?? <dynamic>[],
          'triggered_name_call_events': triggeredForStimulus,
          'audio_video_playback': {
            'method': 'flutter_asset_master_video_with_srt_cues',
            'sync': 'managed_by_flutter_video_player_later',
            'smooth_playlist': true,
            'on_screen_name_call_cue': true,
          },
        },
        'framewise_summary': <String, dynamic>{},
        'triggered_name_call_events': triggeredForStimulus,
      });
    }

    return {
      'stimulus_results': stimulusResults,
      'category_summary': <String, dynamic>{},
      'name_call_events': StimulusProtocolService.getNameCallEvents(schedule),
      'triggered_name_call_events': triggeredEvents,
      'protocol_summary': {
        'total_video_stimuli': timeline.length,
        'total_name_call_events':
            StimulusProtocolService.getNameCallEvents(schedule).length,
        'total_triggered_name_call_events': triggeredEvents.length,
        'uses_tracker_manager': false,
        'measurement_source': 'mobile_master_video_protocol_with_unified_frame_recorder',
        'smooth_playlist': true,
        'playback_backend': 'flutter_asset_master_video',
        'master_video_path': masterVideoAssetPath,
        'master_timeline_path': masterTimelineAssetPath,
        'subtitle_path': 'parent_name_call_cues.srt',
        'on_screen_name_call_cue': true,
        'paper_style_note':
            'Mobile replica generated Python-style raw video protocol files. Framewise CSV recording will be added in the next step.',
      },
    };
  }

  static Map<String, dynamic> buildProtocolSummary({
    required Map<String, dynamic> schedule,
    required Map<String, dynamic> masterTimeline,
    required List<Map<String, dynamic>> triggeredEvents,
  }) {
    final List<Map<String, dynamic>> timeline =
        _timelineFromMaster(masterTimeline);

    return {
      'total_video_stimuli': timeline.length,
      'total_name_call_events': getNameCallEvents(schedule).length,
      'total_triggered_name_call_events': triggeredEvents.length,
      'uses_tracker_manager': false,
      'measurement_source': 'mobile_master_video_protocol_with_unified_frame_recorder',
      'smooth_playlist': true,
      'playback_backend': 'flutter_asset_master_video',
      'master_video_path': masterVideoAssetPath,
      'master_timeline_path': masterTimelineAssetPath,
      'subtitle_path': 'parent_name_call_cues.srt',
      'on_screen_name_call_cue': true,
      'paper_style_note':
          'Matches Python raw protocol metadata. Framewise recorder is not attached yet.',
    };
  }

  static List<Map<String, dynamic>> timelineFromMaster(
    Map<String, dynamic> masterTimeline,
  ) {
    return _timelineFromMaster(masterTimeline);
  }

  static List<Map<String, dynamic>> _timelineFromMaster(
    Map<String, dynamic> masterTimeline,
  ) {
    final dynamic rawTimeline = masterTimeline['timeline'];

    if (rawTimeline is! List) {
      return [];
    }

    return rawTimeline
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static double _toDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }
}