import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../modules/summary/session_summary_screen.dart';
import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/scheduler.dart';
import '../../session/session_assembler.dart';
import 'package:flutter/gestures.dart';

class BubbleGameScreen extends StatefulWidget {
  const BubbleGameScreen({
    super.key,
    required this.sessionDir,
    required this.childInfo,
  });

  final Directory sessionDir;
  final Map<String, dynamic> childInfo;

  @override
  State<BubbleGameScreen> createState() => _BubbleGameScreenState();
}

class _BubbleGameScreenState extends State<BubbleGameScreen>
    with SingleTickerProviderStateMixin {
  static const int gameDurationSec = 35;

  static const double bubbleMinDiameter = 90;
  static const double bubbleMaxDiameter = 150;
  static const double bubbleSpeedMin = 1.5;
  static const double bubbleSpeedMax = 3.0;
  static const double bubbleDriftMax = 0.8;

  static const double spawnIntervalMinSec = 0.4;
  static const double spawnIntervalMaxSec = 1.8;

  static const int particleCount = 18;
  static const double particleSpeedMax = 6;
  static const int particleLifeFrames = 40;
  final AudioPlayer backgroundMusicPlayer = AudioPlayer();

  final List<AudioPlayer> popSoundPlayers = [
    AudioPlayer(),
    AudioPlayer(),
    AudioPlayer(),
  ];

  int popSoundIndex = 0;
  final Random random = Random();

  late final Ticker ticker;

  bool introVisible = true;
  bool gameStarted = false;
  bool gameFinished = false;
  bool saving = false;

  double gameWidth = 0;
  double gameHeight = 0;

  double elapsedSec = 0;
  double nextSpawnInSec = 0;

  int score = 0;
  int missedCount = 0;

  DateTime? gameStartedAt;

  final List<_FloatingBubble> bubbles = [];
  final List<_Particle> particles = [];

  final List<Map<String, dynamic>> reactionLogs = [];
  final List<Map<String, dynamic>> touchEvents = [];

  Map<String, dynamic>? currentTouchEvent;
  double latestPointerPressure = 0.0;
  double latestPointerPressureMin = 0.0;
  double latestPointerPressureMax = 0.0;
  double latestPointerRadiusMajor = 0.0;
  double latestPointerRadiusMinor = 0.0;
  PointerDeviceKind latestPointerKind = PointerDeviceKind.touch;

  @override
  void initState() {
    super.initState();

    ticker = createTicker(handleTick);

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        introVisible = false;
      });
    });
  }

  @override
  void dispose() {
    ticker.dispose();

    backgroundMusicPlayer.dispose();

    for (final AudioPlayer player in popSoundPlayers) {
      player.dispose();
    }

    super.dispose();
  }

  void startGame() {
    if (gameStarted || saving) {
      return;
    }

    setState(() {
      introVisible = false;
      gameStarted = true;
      gameFinished = false;
      saving = false;
      elapsedSec = 0;
      score = 0;
      missedCount = 0;
      bubbles.clear();
      particles.clear();
      reactionLogs.clear();
      touchEvents.clear();
      currentTouchEvent = null;
      gameStartedAt = DateTime.now();
      nextSpawnInSec = randomSpawnInterval();
    });

    ticker.start();
    startBackgroundMusic();
  }

  void handleTick(Duration elapsed) {
    if (!gameStarted || gameFinished) {
      return;
    }

    final double previousElapsed = elapsedSec;

    final DateTime? startedAt = gameStartedAt;
    if (startedAt == null) {
      return;
    }

    elapsedSec = DateTime.now().difference(startedAt).inMilliseconds / 1000.0;

    final double dt = max(0.0, elapsedSec - previousElapsed);

    if (elapsedSec >= gameDurationSec) {
      finishGame();
      return;
    }

    updateGame(dt);

    if (mounted) {
      setState(() {});
    }
  }

  void updateGame(double dt) {
    nextSpawnInSec -= dt;

    if (nextSpawnInSec <= 0) {
      spawnBubble();
      nextSpawnInSec = randomSpawnInterval();
    }

    for (final _FloatingBubble bubble in bubbles) {
      bubble.update();
    }

    final List<_FloatingBubble> aliveBubbles = [];
    final List<_FloatingBubble> deadBubbles = [];

    for (final _FloatingBubble bubble in bubbles) {
      if (bubble.alive) {
        aliveBubbles.add(bubble);
      } else {
        deadBubbles.add(bubble);
      }
    }

    for (final _FloatingBubble bubble in deadBubbles) {
      logMissedBubble(bubble);
    }

    bubbles
      ..clear()
      ..addAll(aliveBubbles);

    for (final _Particle particle in particles) {
      particle.update();
    }

    particles.removeWhere((_Particle particle) => !particle.alive);
  }

  double randomSpawnInterval() {
    return spawnIntervalMinSec +
        random.nextDouble() * (spawnIntervalMaxSec - spawnIntervalMinSec);
  }

  void spawnBubble() {
    if (gameWidth <= 0 || gameHeight <= 0) {
      return;
    }

    final double diameter =
        bubbleMinDiameter +
        random.nextDouble() * (bubbleMaxDiameter - bubbleMinDiameter);

    final double radius = diameter / 2.0;

    final double x =
        radius + random.nextDouble() * max(1, gameWidth - diameter);
    final double y = gameHeight + radius;

    bubbles.add(
      _FloatingBubble(
        id: reactionLogs.length + bubbles.length + 1,
        x: x,
        y: y,
        radius: radius,
        speedY:
            -(bubbleSpeedMin +
                random.nextDouble() * (bubbleSpeedMax - bubbleSpeedMin)),
        driftAmplitude: 0.2 + random.nextDouble() * bubbleDriftMax,
        driftFrequency: 0.01 + random.nextDouble() * 0.02,
        driftPhase: random.nextDouble() * 2 * pi,
        appearTimeSec: elapsedSec,
      ),
    );
  }

  void handlePointerDown(PointerDownEvent event) {
    updateLatestPointerValues(event);
  }

  void handlePointerMove(PointerMoveEvent event) {
    updateLatestPointerValues(event);

    final Map<String, dynamic>? touchEvent = currentTouchEvent;

    if (touchEvent == null) {
      return;
    }

    final List<dynamic> pressureValues =
        touchEvent['pressure_values'] as List<dynamic>;

    final List<dynamic> radiusMajorValues =
        touchEvent['radius_major_values'] as List<dynamic>;

    final List<dynamic> radiusMinorValues =
        touchEvent['radius_minor_values'] as List<dynamic>;

    pressureValues.add(round4(event.pressure));
    radiusMajorValues.add(round4(event.radiusMajor));
    radiusMinorValues.add(round4(event.radiusMinor));
  }

  void handlePointerUp(PointerUpEvent event) {
    updateLatestPointerValues(event);
  }

  void handlePointerCancel(PointerCancelEvent event) {
    updateLatestPointerValues(event);
  }

  void updateLatestPointerValues(PointerEvent event) {
    latestPointerPressure = event.pressure;
    latestPointerPressureMin = event.pressureMin;
    latestPointerPressureMax = event.pressureMax;
    latestPointerRadiusMajor = event.radiusMajor;
    latestPointerRadiusMinor = event.radiusMinor;
    latestPointerKind = event.kind;
  }

  void handlePanStart(DragStartDetails details) {
    if (!gameStarted || gameFinished) {
      return;
    }

    final Offset pos = details.localPosition;

    currentTouchEvent = {
      'touch_id': touchEvents.length + 1,
      'start_time_sec': elapsedSec,
      'end_time_sec': null,
      'duration_seconds': 0,
      'start_x': double.parse(pos.dx.toStringAsFixed(2)),
      'start_y': double.parse(pos.dy.toStringAsFixed(2)),
      'end_x': double.parse(pos.dx.toStringAsFixed(2)),
      'end_y': double.parse(pos.dy.toStringAsFixed(2)),
      'path_points': [
        [
          double.parse(pos.dx.toStringAsFixed(2)),
          double.parse(pos.dy.toStringAsFixed(2)),
        ],
      ],
      'touch_path_length': 0,
      'nearest_bubble_distance': nearestBubbleDistance(pos),
      'hit': false,
      'pointer_kind': latestPointerKind.name,
      'pressure_value': round4(latestPointerPressure),
      'pressure_min': round4(latestPointerPressureMin),
      'pressure_max': round4(latestPointerPressureMax),
      'radius_major': round4(latestPointerRadiusMajor),
      'radius_minor': round4(latestPointerRadiusMinor),
      'pressure_values': [round4(latestPointerPressure)],
      'radius_major_values': [round4(latestPointerRadiusMajor)],
      'radius_minor_values': [round4(latestPointerRadiusMinor)],
      'applied_force_proxy': round4(latestPointerPressure),
      'touch_force_available': latestPointerPressure > 0,
    };

    attemptPop(pos);
  }

  void handlePanUpdate(DragUpdateDetails details) {
    if (!gameStarted || gameFinished) {
      return;
    }

    final Map<String, dynamic>? event = currentTouchEvent;

    if (event == null) {
      return;
    }

    final Offset pos = details.localPosition;

    final List<dynamic> points = event['path_points'] as List<dynamic>;

    points.add([
      double.parse(pos.dx.toStringAsFixed(2)),
      double.parse(pos.dy.toStringAsFixed(2)),
    ]);

    event['end_x'] = double.parse(pos.dx.toStringAsFixed(2));
    event['end_y'] = double.parse(pos.dy.toStringAsFixed(2));
  }

  void handlePanEnd(DragEndDetails details) {
    finishCurrentTouchEvent();
  }

  void handlePanCancel() {
    finishCurrentTouchEvent();
  }

  void finishCurrentTouchEvent() {
    final Map<String, dynamic>? event = currentTouchEvent;

    if (event == null) {
      return;
    }

    event['end_time_sec'] = elapsedSec;
    event['duration_seconds'] = double.parse(
      (elapsedSec - (event['start_time_sec'] as double)).toStringAsFixed(4),
    );

    final List<dynamic> rawPoints = event['path_points'] as List<dynamic>;

    event['touch_path_length'] = double.parse(
      calculatePathLength(rawPoints).toStringAsFixed(4),
    );
    final List<double> pressureValues = dynamicNumberList(
      event['pressure_values'],
    );

    final List<double> radiusMajorValues = dynamicNumberList(
      event['radius_major_values'],
    );

    final List<double> radiusMinorValues = dynamicNumberList(
      event['radius_minor_values'],
    );

    event['average_pressure'] = round4(mean(pressureValues));
    event['max_pressure'] = round4(maxValue(pressureValues));
    event['average_radius_major'] = round4(mean(radiusMajorValues));
    event['average_radius_minor'] = round4(mean(radiusMinorValues));
    event['applied_force_proxy'] = round4(mean(pressureValues));
    event['touch_force_available'] = pressureValues.any(
      (double value) => value > 0,
    );

    touchEvents.add(event);

    currentTouchEvent = null;
  }

  void attemptPop(Offset pos) {
    _FloatingBubble? hitBubble;

    for (final _FloatingBubble bubble in bubbles.reversed) {
      if (bubble.contains(pos)) {
        hitBubble = bubble;
        break;
      }
    }

    final bool hit = hitBubble != null;

    if (currentTouchEvent != null) {
      currentTouchEvent!['hit'] = hit;
      currentTouchEvent!['nearest_bubble_distance'] = double.parse(
        nearestBubbleDistance(pos).toStringAsFixed(4),
      );
    }

    if (hitBubble == null) {
      return;
    }

    bubbles.remove(hitBubble);

    final double reactionTimeSec = elapsedSec - hitBubble.appearTimeSec;

    reactionLogs.add({
      'x': double.parse(hitBubble.x.toStringAsFixed(2)),
      'y': double.parse(hitBubble.y.toStringAsFixed(2)),
      'reaction_time_sec': double.parse(reactionTimeSec.toStringAsFixed(2)),
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'popped',
    });

    score += 1;
    playPopSound();
    keepBackgroundMusicAlive();

    for (int i = 0; i < particleCount; i++) {
      particles.add(
        _Particle.random(
          random: random,
          x: hitBubble.x,
          y: hitBubble.y,
          maxSpeed: particleSpeedMax,
          maxLife: particleLifeFrames,
        ),
      );
    }
  }

  void logMissedBubble(_FloatingBubble bubble) {
    missedCount += 1;

    reactionLogs.add({
      'x': double.parse(bubble.x.toStringAsFixed(2)),
      'y': double.parse(bubble.y.toStringAsFixed(2)),
      'reaction_time_sec': '',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'missed',
    });
  }

  Future<void> finishGame() async {
    if (gameFinished) {
      return;
    }

    ticker.stop();
    await stopBackgroundMusic();

    for (final _FloatingBubble bubble in bubbles) {
      logMissedBubble(bubble);
    }

    bubbles.clear();

    finishCurrentTouchEvent();

    setState(() {
      gameStarted = false;
      gameFinished = true;
      saving = true;
      elapsedSec = gameDurationSec.toDouble();
    });

    await saveGameOutputs();

    if (!mounted) {
      return;
    }

    setState(() {
      saving = false;
    });
  }

  Future<void> saveGameOutputs() async {
    final List<Map<String, dynamic>> popped = reactionLogs
        .where((Map<String, dynamic> log) => log['status'] == 'popped')
        .toList();

    final List<Map<String, dynamic>> missed = reactionLogs
        .where((Map<String, dynamic> log) => log['status'] == 'missed')
        .toList();

    final List<double> reactionTimesSec = popped
        .map((Map<String, dynamic> log) => log['reaction_time_sec'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .toList();

    final double averageReactionTimeSec = mean(reactionTimesSec);
    final double reactionVariance = variance(reactionTimesSec);
    final int totalBubbles = reactionLogs.length;

    final double missRatio = totalBubbles == 0
        ? 0.0
        : missed.length / totalBubbles;

    final Map<String, dynamic> touchFeatures = buildTouchFeatures();

    final Map<String, dynamic> behavioralPhenotypes = {
      'attention_deficit': round2(min(averageReactionTimeSec / 3.0, 1.0)),
      'disengagement': round2(missRatio),
      'motor_irregularity': round2(min(reactionVariance, 1.0)),
      'responsiveness': round2(min(score / 20.0, 1.0)),
    };

    final Map<String, dynamic> gameMetrics = {
      'schema_version': 'python_mobile_replica_bubble_game_metrics_v2',
      'generated_at': DateTime.now().toIso8601String(),
      'score': score,
      'total_reactions': reactionLogs.length,
      'reaction_data': reactionLogs,
      'behavioral_phenotypes': behavioralPhenotypes,
      'touch_events': touchEvents,
      'touch_features': touchFeatures,
      'paper_pop_the_bubbles_popping_rate':
          touchFeatures['touch_popping_rate'] ?? 0,
      'paper_pop_the_bubbles_accuracy_std':
          touchFeatures['touch_error_std'] ?? 0,
      'paper_pop_the_bubbles_average_touch_length':
          touchFeatures['touch_average_length'] ?? 0,
      'paper_pop_the_bubbles_average_applied_force':
          touchFeatures['touch_average_applied_force'] ?? 0,
      'touch_force_available': touchFeatures['touch_force_available'] == true,
      'game_duration_sec': gameDurationSec,
      'spawn_interval_min_sec': spawnIntervalMinSec,
      'spawn_interval_max_sec': spawnIntervalMaxSec,
      'bubble_min_diameter': bubbleMinDiameter,
      'bubble_max_diameter': bubbleMaxDiameter,
      'measurement_source':
          'flutter_touchscreen_python_style_bubble_game_with_pointer_pressure',
      'reaction_log_file': SessionFileNames.bubbleGameReactions,
    };

    await SessionService.saveCsv(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.bubbleGameReactions,
      headers: const ['x', 'y', 'reaction_time_sec', 'timestamp', 'status'],
      rows: reactionLogs.map((Map<String, dynamic> log) {
        return [
          log['x'],
          log['y'],
          log['reaction_time_sec'],
          log['timestamp'],
          log['status'],
        ];
      }).toList(),
    );

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.gameMetrics,
      data: gameMetrics,
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
          'framewise_logs',
          'bubble_game',
        ],
        'files': {
          SessionFileNames.childInfo: true,
          SessionFileNames.scqResults: true,
          SessionFileNames.stimulusProtocolSummary: true,
          SessionFileNames.stimulusEvents: true,
          SessionFileNames.videoTest: true,
          SessionFileNames.parentNameCallCues: true,
          SessionFileNames.framewiseFaceSignals: true,
          SessionFileNames.gameMetrics: true,
          SessionFileNames.bubbleGameReactions: true,
        },
        'game_metrics': gameMetrics,
      },
    );
    await SessionAssembler.buildAndSave(sessionDir: widget.sessionDir);
  }

  Map<String, dynamic> buildTouchFeatures() {
    final int totalTouches = touchEvents.length;

    final int hitTouches = touchEvents
        .where((Map<String, dynamic> event) => event['hit'] == true)
        .length;

    final List<double> lengths = touchEvents
        .map((Map<String, dynamic> event) => event['touch_path_length'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .toList();

    final List<double> errors = touchEvents
        .map((Map<String, dynamic> event) => event['nearest_bubble_distance'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .toList();
    final List<double> appliedForceValues = touchEvents
        .map((Map<String, dynamic> event) => event['applied_force_proxy'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .where((double value) => value > 0)
        .toList();

    final List<double> radiusMajorValues = touchEvents
        .map((Map<String, dynamic> event) => event['average_radius_major'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .where((double value) => value > 0)
        .toList();

    final List<double> radiusMinorValues = touchEvents
        .map((Map<String, dynamic> event) => event['average_radius_minor'])
        .whereType<num>()
        .map((num value) => value.toDouble())
        .where((double value) => value > 0)
        .toList();

    final bool touchForceAvailable = appliedForceValues.isNotEmpty;

    return {
      'touch_count': totalTouches,
      'touch_hit_count': hitTouches,
      'touch_popping_rate': round4(score / gameDurationSec),
      'touch_accuracy': totalTouches == 0
          ? 0.0
          : round4(hitTouches / totalTouches),
      'touch_error_std': round4(std(errors)),
      'touch_average_length': round4(mean(lengths)),
      'touch_average_applied_force': touchForceAvailable
          ? round4(mean(appliedForceValues))
          : null,
      'touch_force_available': touchForceAvailable,
      'touch_average_radius_major': radiusMajorValues.isEmpty
          ? null
          : round4(mean(radiusMajorValues)),
      'touch_average_radius_minor': radiusMinorValues.isEmpty
          ? null
          : round4(mean(radiusMinorValues)),
    };
  }

  double nearestBubbleDistance(Offset pos) {
    if (bubbles.isEmpty) {
      return 0.0;
    }

    double nearest = double.infinity;

    for (final _FloatingBubble bubble in bubbles) {
      final double dx = bubble.x - pos.dx;
      final double dy = bubble.y - pos.dy;
      final double distance = sqrt(dx * dx + dy * dy);

      if (distance < nearest) {
        nearest = distance;
      }
    }

    return nearest == double.infinity ? 0.0 : nearest;
  }

  double calculatePathLength(List<dynamic> points) {
    if (points.length <= 1) {
      return 0.0;
    }

    double total = 0.0;

    for (int i = 1; i < points.length; i++) {
      final List<dynamic> previous = points[i - 1] as List<dynamic>;
      final List<dynamic> current = points[i] as List<dynamic>;

      final double px = (previous[0] as num).toDouble();
      final double py = (previous[1] as num).toDouble();
      final double cx = (current[0] as num).toDouble();
      final double cy = (current[1] as num).toDouble();

      final double dx = cx - px;
      final double dy = cy - py;

      total += sqrt(dx * dx + dy * dy);
    }

    return total;
  }

  List<double> dynamicNumberList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value.whereType<num>().map((num item) => item.toDouble()).toList();
  }

  double maxValue(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce(max);
  }

  double mean(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce((double a, double b) => a + b) / values.length;
  }

  double variance(List<double> values) {
    if (values.length <= 1) {
      return 0.0;
    }

    final double avg = mean(values);

    return values
            .map((double value) => pow(value - avg, 2).toDouble())
            .reduce((double a, double b) => a + b) /
        values.length;
  }

  double std(List<double> values) {
    return sqrt(variance(values));
  }

  double round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  double round4(double value) {
    return double.parse(value.toStringAsFixed(4));
  }

  void goToSummary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return SessionSummaryScreen(
            sessionDir: widget.sessionDir,
            childInfo: widget.childInfo,
          );
        },
      ),
    );
  }

  Future<void> startBackgroundMusic() async {
    try {
      await backgroundMusicPlayer.stop();
      await backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await backgroundMusicPlayer.setVolume(0.35);

      await backgroundMusicPlayer.play(
        AssetSource('bubble_game/music.mp3'),
        volume: 0.35,
      );
    } catch (_) {
      // Keep game running even if audio fails.
    }
  }

  Future<void> keepBackgroundMusicAlive() async {
    try {
      final PlayerState state = backgroundMusicPlayer.state;

      if (gameStarted && state != PlayerState.playing) {
        await backgroundMusicPlayer.resume();
      }
    } catch (_) {
      // Ignore music recovery errors.
    }
  }

  Future<void> stopBackgroundMusic() async {
    try {
      await backgroundMusicPlayer.stop();
    } catch (_) {
      // Ignore audio stop errors.
    }
  }

  Future<void> playPopSound() async {
    try {
      final AudioPlayer player = popSoundPlayers[popSoundIndex];

      popSoundIndex = (popSoundIndex + 1) % popSoundPlayers.length;

      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(0.85);

      await player.seek(Duration.zero);

      await player.play(AssetSource('bubble_game/pop.mp3'), volume: 0.85);
    } catch (_) {
      // Keep game running even if pop sound fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final double timeLeft = max(0, gameDurationSec - elapsedSec);
    final int timeLeftRounded = timeLeft.ceil();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            gameWidth = constraints.maxWidth;
            gameHeight = constraints.maxHeight;

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: handlePointerDown,
              onPointerMove: handlePointerMove,
              onPointerUp: handlePointerUp,
              onPointerCancel: handlePointerCancel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: handlePanStart,
                onPanUpdate: handlePanUpdate,
                onPanEnd: handlePanEnd,
                onPanCancel: handlePanCancel,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/bubble_game/GAMEBG.jpg',
                      fit: BoxFit.cover,
                    ),

                    for (final _FloatingBubble bubble in bubbles)
                      Positioned(
                        left: bubble.x - bubble.radius,
                        top: bubble.y - bubble.radius,
                        width: bubble.radius * 2,
                        height: bubble.radius * 2,
                        child: Image.asset(
                          'assets/bubble_game/bubble.png',
                          fit: BoxFit.contain,
                        ),
                      ),

                    for (final _Particle particle in particles)
                      Positioned(
                        left: particle.x - particle.radius,
                        top: particle.y - particle.radius,
                        child: Opacity(
                          opacity: particle.opacity,
                          child: Container(
                            width: particle.radius * 2,
                            height: particle.radius * 2,
                            decoration: BoxDecoration(
                              color: particle.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),

                    if (introVisible)
                      _IntroOverlay(
                        onSkip: () {
                          setState(() {
                            introVisible = false;
                          });
                        },
                      ),

                    if (!gameStarted && !gameFinished && !introVisible)
                      Center(
                        child: ElevatedButton(
                          onPressed: startGame,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 18,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: const Text('Start Bubble Game'),
                        ),
                      ),

                    if (gameStarted)
                      Positioned(
                        left: 20,
                        top: 20,
                        child: _HudText(
                          text: 'Score: $score',
                          color: const Color(0xFFFFE632),
                          alignRight: false,
                        ),
                      ),

                    if (gameStarted)
                      Positioned(
                        right: 20,
                        top: 20,
                        child: _HudText(
                          text: 'Time: ${timeLeftRounded}s',
                          color: timeLeft <= 10
                              ? const Color(0xFFFF4040)
                              : const Color(0xFFFF78B4),
                          alignRight: true,
                        ),
                      ),

                    if (saving)
                      Container(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Center(child: CircularProgressIndicator()),
                      ),

                    if (gameFinished && !saving)
                      _EndOverlay(score: score, onContinue: goToSummary),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingBubble {
  _FloatingBubble({
    required this.id,
    required this.x,
    required this.y,
    required this.radius,
    required this.speedY,
    required this.driftAmplitude,
    required this.driftFrequency,
    required this.driftPhase,
    required this.appearTimeSec,
  });

  final int id;
  double x;
  double y;
  final double radius;
  final double speedY;
  final double driftAmplitude;
  final double driftFrequency;
  final double driftPhase;
  final double appearTimeSec;

  int age = 0;
  bool alive = true;

  void update() {
    age += 1;

    y += speedY;

    x += driftAmplitude * sin(driftFrequency * age + driftPhase);

    if (y + radius < 0) {
      alive = false;
    }
  }

  bool contains(Offset pos) {
    final double dx = x - pos.dx;
    final double dy = y - pos.dy;

    return sqrt(dx * dx + dy * dy) <= radius;
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
    required this.maxLife,
    required this.radius,
  });

  factory _Particle.random({
    required Random random,
    required double x,
    required double y,
    required double maxSpeed,
    required int maxLife,
  }) {
    final double angle = random.nextDouble() * 2 * pi;
    final double speed = 1.5 + random.nextDouble() * maxSpeed;

    final List<Color> colors = [
      const Color(0xFFFFE632),
      const Color(0xFFFF78B4),
      const Color(0xFF50BEFF),
      const Color(0xFF64F064),
      const Color(0xFFFFA028),
      const Color(0xFFC864FF),
      Colors.white,
    ];

    return _Particle(
      x: x,
      y: y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: colors[random.nextInt(colors.length)],
      life: maxLife,
      maxLife: maxLife,
      radius: 4 + random.nextDouble() * 5,
    );
  }

  double x;
  double y;
  double vx;
  double vy;
  final Color color;
  int life;
  final int maxLife;
  final double radius;

  bool get alive => life > 0;

  double get opacity {
    if (maxLife <= 0) {
      return 0;
    }

    return max(0, min(1, life / maxLife));
  }

  void update() {
    x += vx;
    y += vy;

    vy += 0.15;
    vx *= 0.97;

    life -= 1;
  }
}

class _IntroOverlay extends StatelessWidget {
  const _IntroOverlay({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSkip,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bubble_game/GAMEBG.jpg', fit: BoxFit.cover),
          Positioned(
            left: 20,
            bottom: 20,
            width: MediaQuery.of(context).size.width * 0.43,
            child: Image.asset(
              'assets/bubble_game/character.png',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: MediaQuery.of(context).size.width * 0.38,
            right: 20,
            bottom: MediaQuery.of(context).size.height * 0.28,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: const Text(
                'Hey! Pop as many bubbles as you can!',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudText extends StatelessWidget {
  const _HudText({
    required this.text,
    required this.color,
    required this.alignRight,
  });

  final String text;
  final Color color;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Transform.translate(
          offset: const Offset(3, 3),
          child: Text(
            text,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          text,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: color,
            fontSize: 42,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({required this.score, required this.onContinue});

  final int score;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC14143C),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Time's up!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Final Score: $score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onContinue,
                child: const Text('Continue to session summary'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
