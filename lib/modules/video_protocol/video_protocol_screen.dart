import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'framewise_log_exporter.dart';
import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import 'stimulus_protocol_service.dart';
import '../../native/native_face_recorder_service.dart';
import 'calibrated_gaze_builder.dart';
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
  void initState() {
    super.initState();
    enterLandscapeFullscreen();
  }

  Future<void> enterLandscapeFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> exitLandscapeFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    cueTimer?.cancel();
    controller?.dispose();
    exitLandscapeFullscreen();
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
    final Map<String, dynamic> calibratedGazePayload =
        await CalibratedGazeBuilder.buildAndSave(sessionDir: widget.sessionDir);

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
      'calibrated_gaze': {
        'enabled': true,
        'file': SessionFileNames.calibratedGazeFrames,
        'status': calibratedGazePayload['status'],
        'frame_count': calibratedGazePayload['frame_count'],
        'valid_gaze_frame_count':
            calibratedGazePayload['valid_gaze_frame_count'],
        'valid_gaze_ratio': calibratedGazePayload['valid_gaze_ratio'],
        'source': 'mobile_unified_recorder_iris_calibrated_gaze',
      },
      'actual_name_call_trigger_logging': {
        'enabled': true,
        'method': 'flutter_video_player_position_timer',
        'timer_interval_ms': 100,
        'trigger_window_sec': 0.35,
        'scheduled_count': scheduledEvents.length,
        'observed_triggered_count': observedTriggeredCount,
        'events_file': SessionFileNames.stimulusEvents,
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
    final VideoPlayerController? videoController = controller;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        await exitLandscapeFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child:
                    videoController == null ||
                        !videoController.value.isInitialized
                    ? buildPreparationView()
                    : buildVideoView(videoController),
              ),

              if (activeParentCue.isNotEmpty)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: buildParentCueOverlay(),
                ),

              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: buildBottomControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildPreparationView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Video Session',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Keep the child facing the screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 17),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isPreparing ? null : prepareProtocolFiles,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isPreparing ? 'Preparing...' : 'Prepare'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildVideoView(VideoPlayerController videoController) {
    final Size videoSize = videoController.value.size;

    return Center(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: videoSize.width,
          height: videoSize.height,
          child: VideoPlayer(videoController),
        ),
      ),
    );
  }

  Widget buildParentCueOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(18),
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
    );
  }

  Widget buildBottomControls() {
    if (playbackCompleted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: goToBubbleGame,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      );
    }

    if (!isPrepared) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: isPlaying ? null : playVideo,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }

  Future<void> goToBubbleGame() async {
    await exitLandscapeFullscreen();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return BubbleGameScreen(
            sessionDir: widget.sessionDir,
            childInfo: widget.childInfo,
          );
        },
      ),
    );
  }
}
