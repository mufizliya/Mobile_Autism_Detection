import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'framewise_log_exporter.dart';
import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import 'stimulus_protocol_service.dart';
import '../../native/native_face_recorder_service.dart';
//import '../../native/native_iris_recorder_service.dart';
//import 'calibrated_gaze_builder.dart';
import '../bubble_game/bubble_game_screen.dart';

class VideoProtocolScreen extends StatefulWidget {
  const VideoProtocolScreen({
    super.key,
    required this.sessionDir,
    required this.childInfo,
  });

  final Directory sessionDir;
  final Map<String, dynamic> childInfo;

  @override
  State<VideoProtocolScreen> createState() => _VideoProtocolScreenState();
}

class _VideoProtocolScreenState extends State<VideoProtocolScreen> {
  VideoPlayerController? controller;
  Timer? cueTimer;

  bool isPreparing = false;
  bool isPrepared = false;
  bool isPlaying = false;
  bool playbackCompleted = false;

  String status = 'Video protocol not prepared yet.';
  String activeParentCue = '';

  Map<String, dynamic>? loadedSchedule;
  Map<String, dynamic>? loadedMasterTimeline;
  final List<Map<String, dynamic>> actualTriggeredNameCallEvents = [];

  final Set<String> alreadyLoggedNameCallIds = {};

  List<Map<String, dynamic>> timeline = [];
  List<Map<String, dynamic>> scheduledEvents = [];
  List<Map<String, dynamic>> triggeredEvents = [];

  DateTime? playbackStartedAt;
  DateTime? playbackCompletedAt;

  @override
  void dispose() {
    cueTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> prepareProtocolFiles() async {
    setState(() {
      isPreparing = true;
      status = 'Loading stimulus schedule and master timeline...';
    });

    final Map<String, dynamic> schedule =
        await StimulusProtocolService.loadSchedule();

    final Map<String, dynamic> masterTimeline =
        await StimulusProtocolService.loadMasterTimeline();

    final List<Map<String, dynamic>> parsedTimeline =
        StimulusProtocolService.timelineFromMaster(masterTimeline);

    final List<Map<String, dynamic>> parsedScheduledEvents =
        StimulusProtocolService.collectScheduledNameCallEvents(parsedTimeline);

    final List<Map<String, dynamic>> parsedTriggeredEvents =
        StimulusProtocolService.buildTriggeredNameCallEvents(
          parsedScheduledEvents,
        );

    final String childName = widget.childInfo['name']?.toString().trim() ?? '';

    final String parentCueSrt = StimulusProtocolService.buildParentCueSrt(
      timeline: parsedTimeline,
      childName: childName,
    );

    final Map<String, dynamic> protocolSummary =
        StimulusProtocolService.buildProtocolSummary(
          schedule: schedule,
          masterTimeline: masterTimeline,
          triggeredEvents: parsedTriggeredEvents,
        );

    final Map<String, dynamic> stimulusEvents = {
      'scheduled_name_call_events': parsedScheduledEvents,
      'triggered_name_call_events': parsedTriggeredEvents,
    };

    final Map<String, dynamic> videoTest =
        StimulusProtocolService.buildVideoTestSkeleton(
          schedule: schedule,
          masterTimeline: masterTimeline,
          triggeredEvents: parsedTriggeredEvents,
        );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.stimulusProtocolSummary,
      data: protocolSummary,
    );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.stimulusEvents,
      data: stimulusEvents,
    );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.videoTest,
      data: videoTest,
    );

    await SessionService.fileInSession(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.parentNameCallCues,
    ).writeAsString(parentCueSrt, flush: true);

    final VideoPlayerController newController = VideoPlayerController.asset(
      StimulusProtocolService.masterVideoAssetPath,
    );

    await newController.initialize();

    newController.addListener(handleVideoState);

    await controller?.dispose();

    controller = newController;

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'updated_at': DateTime.now().toIso8601String(),
        'completed_modules': ['child_info', 'scq', 'video_protocol_raw_files'],

        'files': {
          SessionFileNames.childInfo: true,
          SessionFileNames.scqResults: true,
          SessionFileNames.stimulusProtocolSummary: true,
          SessionFileNames.stimulusEvents: true,
          SessionFileNames.videoTest: true,
          SessionFileNames.parentNameCallCues: true,
        },
        'video_test': videoTest,
      },
    );

    if (!mounted) return;

    setState(() {
      loadedSchedule = schedule;
      loadedMasterTimeline = masterTimeline;
      timeline = parsedTimeline;
      scheduledEvents = parsedScheduledEvents;
      triggeredEvents = parsedTriggeredEvents;

      isPreparing = false;
      isPrepared = true;
      status =
          'Raw video protocol files generated and master video loaded.\n'
          'Video stimuli: ${timeline.length}\n'
          'Scheduled name calls: ${scheduledEvents.length}\n'
          'Triggered name calls: ${triggeredEvents.length}\n\n'
          'Now tap Play master protocol video.';
    });
  }

  Future<void> playVideo() async {
    final VideoPlayerController? currentController = controller;

    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }

    playbackStartedAt = DateTime.now();
    playbackCompletedAt = null;
    playbackCompleted = false;
    actualTriggeredNameCallEvents.clear();
    alreadyLoggedNameCallIds.clear();

    await NativeFaceRecorderService.start();
    // try {
    //   await NativeIrisRecorderService.start();
    // } catch (error) {
    //   debugPrint('Iris recorder start failed: $error');
    // }
    await currentController.seekTo(Duration.zero);
    await currentController.play();

    cueTimer?.cancel();

    cueTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => updateParentCue(),
    );

    if (!mounted) return;

    setState(() {
      isPlaying = true;
      activeParentCue = '';
      status = 'Playing master protocol video...';
    });

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.videoTest,
      updates: {
        'mobile_playback': {
          'status': 'started',
          'started_at': playbackStartedAt!.toIso8601String(),
          'master_video_asset': StimulusProtocolService.masterVideoAssetPath,
        },
      },
    );
  }

  Future<void> pauseVideo() async {
    final VideoPlayerController? currentController = controller;

    if (currentController == null) return;

    await currentController.pause();

    cueTimer?.cancel();

    if (!mounted) return;

    setState(() {
      isPlaying = false;
      activeParentCue = '';
      status = 'Video paused.';
    });
  }

  void updateParentCue() {
    final VideoPlayerController? currentController = controller;

    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }

    final double currentSec =
        currentController.value.position.inMilliseconds / 1000.0;

    logActualNameCallEvents(currentSec: currentSec);

    final String childName = widget.childInfo['name']?.toString().trim() ?? '';

    String cue = '';

    for (final Map<String, dynamic> event in scheduledEvents) {
      final double callTime = toDouble(event['global_call_time_sec']);

      if (currentSec >= callTime && currentSec <= callTime + 1.5) {
        cue = childName.isNotEmpty
            ? 'CALL $childName NOW'
            : 'CALL CHILD NAME NOW';
        break;
      }
    }

    if (cue != activeParentCue && mounted) {
      setState(() {
        activeParentCue = cue;
      });
    }
  }

  void logActualNameCallEvents({required double currentSec}) {
    for (final Map<String, dynamic> event in scheduledEvents) {
      final String eventId = event['id']?.toString() ?? '';

      if (eventId.isEmpty) {
        continue;
      }

      if (alreadyLoggedNameCallIds.contains(eventId)) {
        continue;
      }

      final double scheduledGlobalSec = toDouble(event['global_call_time_sec']);

      final double delayFromScheduleSec = currentSec - scheduledGlobalSec;

      if (delayFromScheduleSec < 0 || delayFromScheduleSec > 0.35) {
        continue;
      }

      final Map<String, dynamic> actualEvent = Map<String, dynamic>.from(event);

      actualEvent.addAll({
        'triggered': true,
        'actual_global_trigger_time_sec': double.parse(
          currentSec.toStringAsFixed(3),
        ),
        'actual_trigger_delay_from_schedule_sec': double.parse(
          delayFromScheduleSec.toStringAsFixed(3),
        ),
        'actual_wall_time_iso': DateTime.now().toIso8601String(),
        'trigger_source': 'flutter_video_playback_timer',
      });

      actualTriggeredNameCallEvents.add(actualEvent);
      alreadyLoggedNameCallIds.add(eventId);
    }
  }

  Future<void> handleVideoCompleted() async {
    if (playbackCompleted) {
      return;
    }

    playbackCompleted = true;
    playbackCompletedAt = DateTime.now();

    cueTimer?.cancel();

    for (final Map<String, dynamic> event in scheduledEvents) {
      final String eventId = event['id']?.toString() ?? '';

      if (eventId.isEmpty || alreadyLoggedNameCallIds.contains(eventId)) {
        continue;
      }

      final Map<String, dynamic> fallbackEvent = Map<String, dynamic>.from(
        event,
      );

      fallbackEvent.addAll({
        'triggered': false,
        'actual_global_trigger_time_sec': null,
        'actual_trigger_delay_from_schedule_sec': null,
        'actual_wall_time_iso': null,
        'trigger_source': 'not_observed_during_playback',
      });

      actualTriggeredNameCallEvents.add(fallbackEvent);
      alreadyLoggedNameCallIds.add(eventId);
    }

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.stimulusEvents,
      data: {
        'scheduled_name_call_events': scheduledEvents,
        'triggered_name_call_events': actualTriggeredNameCallEvents,
        'trigger_logging': {
          'schema_version':
              'mobile_actual_playback_name_call_trigger_logging_v1',
          'generated_at': DateTime.now().toIso8601String(),
          'method': 'flutter_video_player_position_timer',
          'timer_interval_ms': 100,
          'trigger_window_sec': 0.35,
          'total_scheduled': scheduledEvents.length,
          'total_triggered_observed': actualTriggeredNameCallEvents
              .where((Map<String, dynamic> event) => event['triggered'] == true)
              .length,
        },
      },
    );

    Map<String, dynamic>? framewisePayload;

    try {
      framewisePayload = await NativeFaceRecorderService.stopAndSave(
        sessionDir: widget.sessionDir,
      );
    } catch (error) {
      framewisePayload = {'error': error.toString()};
    }
    // Map<String, dynamic>? irisPayload;

    // try {
    //   irisPayload = await NativeIrisRecorderService.stopAndSave(
    //     sessionDir: widget.sessionDir,
    //     fileName: SessionFileNames.videoIrisSignals,
    //   );
    // } catch (error) {
    //   debugPrint('Iris recorder stop/save failed: $error');
    // }
    // final Map<String, dynamic> calibratedGazePayload =
    //     await CalibratedGazeBuilder.buildAndSave(sessionDir: widget.sessionDir);

    Map<String, dynamic>? framewiseExportSummary;

    if (framewisePayload['frames'] is List) {
      framewiseExportSummary = await FramewiseLogExporter.exportPerStimulusLogs(
        sessionDir: widget.sessionDir,
        framewiseSignals: framewisePayload,
        timeline: timeline,
      );
    }

    final VideoPlayerController? currentController = controller;

    final double durationSec = currentController == null
        ? 0.0
        : currentController.value.duration.inMilliseconds / 1000.0;

    final int observedTriggeredCount = actualTriggeredNameCallEvents
        .where((Map<String, dynamic> event) => event['triggered'] == true)
        .length;

    final Map<String, dynamic> playbackSummary = {
      'framewise_recording_attached': true,
      'framewise_face_signals_file': SessionFileNames.framewiseFaceSignals,
      'framewise_face_signals_summary': framewisePayload['summary'],
      'framewise_csv_export': framewiseExportSummary,
      //'Calibrated gaze frames: ${calibratedGazePayload['valid_gaze_frame_count']}'
      'actual_name_call_trigger_logging': {
        'enabled': true,
        'method': 'flutter_video_player_position_timer',
        'timer_interval_ms': 100,
        'trigger_window_sec': 0.35,
        'scheduled_count': scheduledEvents.length,
        'observed_triggered_count': observedTriggeredCount,
        'events_file': SessionFileNames.stimulusEvents,
      },
      'iris_landmark_recording': {
        'enabled': true,
        'file': SessionFileNames.videoIrisSignals,
        // 'frame_count': irisPayload?['frame_count'],
        // 'summary': irisPayload?['summary'],
        'source': 'mediapipe_face_landmarker_iris',
      },
      'status': 'completed',
      'started_at': playbackStartedAt?.toIso8601String(),
      'completed_at': playbackCompletedAt?.toIso8601String(),
      'duration_sec': double.parse(durationSec.toStringAsFixed(3)),
      'master_video_asset': StimulusProtocolService.masterVideoAssetPath,
    };

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.videoTest,
      updates: {'mobile_playback': playbackSummary},
    );

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'updated_at': DateTime.now().toIso8601String(),
        'completed_modules': [
          'child_info',
          'scq',
          'video_protocol_raw_files',
          'video_protocol_playback',
        ],
        'video_playback': playbackSummary,
      },
    );

    if (!mounted) return;

    setState(() {
      isPlaying = false;
      activeParentCue = '';
      status =
          'Master video playback completed.\n\n'
          'Framewise recorder saved.\n'
          'Per-stimulus CSV logs generated.\n'
          'Actual playback-time name-call events logged.\n\n'
          'Continue to bubble game.';
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video playback completed.')));
  }

  void handleVideoState() {
    final VideoPlayerController? currentController = controller;

    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }

    final Duration position = currentController.value.position;
    final Duration duration = currentController.value.duration;

    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 300) {
      handleVideoCompleted();
    }
  }

  double toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final String childName = widget.childInfo['name']?.toString().trim() ?? '';

    final VideoPlayerController? currentController = controller;
    final bool videoReady =
        currentController != null && currentController.value.isInitialized;

    return Scaffold(
      appBar: AppBar(title: const Text('Video Protocol')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Child: $childName',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This step plays the master protocol video and shows parent name-call cues. '
                      'Framewise CSV recording is not attached yet.',
                    ),
                    const SizedBox(height: 20),

                    if (videoReady)
                      AspectRatio(
                        aspectRatio: currentController.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(currentController),
                            if (activeParentCue.isNotEmpty)
                              Positioned(
                                bottom: 24,
                                left: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    activeParentCue,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 220,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Master video not loaded yet.'),
                      ),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: isPreparing ? null : prepareProtocolFiles,
                      child: isPreparing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              isPrepared
                                  ? 'Reload video protocol files'
                                  : 'Prepare video protocol raw files',
                            ),
                    ),

                    const SizedBox(height: 12),

                    if (isPrepared)
                      ElevatedButton(
                        onPressed: isPlaying ? pauseVideo : playVideo,
                        child: Text(
                          isPlaying
                              ? 'Pause video'
                              : 'Play master protocol video',
                        ),
                      ),
                    if (playbackCompleted)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (BuildContext context) {
                                  return BubbleGameScreen(
                                    sessionDir: widget.sessionDir,
                                    childInfo: widget.childInfo,
                                  );
                                },
                              ),
                            );
                          },
                          child: const Text('Continue to bubble game'),
                        ),
                      ),

                    const SizedBox(height: 20),

                    SelectableText(status),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
