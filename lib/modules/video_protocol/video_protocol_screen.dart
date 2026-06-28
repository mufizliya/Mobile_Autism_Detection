import 'dart:io';

import 'package:flutter/material.dart';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import 'stimulus_protocol_service.dart';

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
  bool isPreparing = false;
  String status = 'Video protocol not prepared yet.';

  Future<void> prepareProtocolFiles() async {
    setState(() {
      isPreparing = true;
      status = 'Loading stimulus schedule and master timeline...';
    });

    final Map<String, dynamic> schedule =
        await StimulusProtocolService.loadSchedule();

    final Map<String, dynamic> masterTimeline =
        await StimulusProtocolService.loadMasterTimeline();

    final List<Map<String, dynamic>> timeline =
        StimulusProtocolService.timelineFromMaster(masterTimeline);

    final List<Map<String, dynamic>> scheduledEvents =
        StimulusProtocolService.collectScheduledNameCallEvents(timeline);

    final List<Map<String, dynamic>> triggeredEvents =
        StimulusProtocolService.buildTriggeredNameCallEvents(scheduledEvents);

    final String childName =
        widget.childInfo['name']?.toString().trim() ?? '';

    final String parentCueSrt = StimulusProtocolService.buildParentCueSrt(
      timeline: timeline,
      childName: childName,
    );

    final Map<String, dynamic> protocolSummary =
        StimulusProtocolService.buildProtocolSummary(
      schedule: schedule,
      masterTimeline: masterTimeline,
      triggeredEvents: triggeredEvents,
    );

    final Map<String, dynamic> stimulusEvents = {
      'scheduled_name_call_events': scheduledEvents,
      'triggered_name_call_events': triggeredEvents,
    };

    final Map<String, dynamic> videoTest =
        StimulusProtocolService.buildVideoTestSkeleton(
      schedule: schedule,
      masterTimeline: masterTimeline,
      triggeredEvents: triggeredEvents,
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
    ).writeAsString(
      parentCueSrt,
      flush: true,
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
        ],
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

    if (!mounted) {
      return;
    }

    setState(() {
      isPreparing = false;
      status = 'Generated raw video protocol files.\n'
          'Video stimuli: ${timeline.length}\n'
          'Scheduled name calls: ${scheduledEvents.length}\n'
          'Triggered name calls: ${triggeredEvents.length}\n\n'
          'Session:\n${widget.sessionDir.path}';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video protocol raw files generated.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String childName =
        widget.childInfo['name']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Protocol'),
      ),
      body: SafeArea(
        child: Padding(
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
                'This step prepares Python-style raw video protocol files only. '
                'Actual video playback and framewise CSV recording will be added next.',
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isPreparing ? null : prepareProtocolFiles,
                child: isPreparing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Prepare video protocol raw files'),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(status),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}