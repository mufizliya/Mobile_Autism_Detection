import 'dart:io';

import 'package:flutter/material.dart';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../../session/session_assembler.dart';

class SessionSummaryScreen extends StatefulWidget {
  const SessionSummaryScreen({
    super.key,
    required this.sessionDir,
    required this.childInfo,
  });

  final Directory sessionDir;
  final Map<String, dynamic> childInfo;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  Map<String, dynamic>? finalSession;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadSummary();
  }

  Future<void> loadSummary() async {
    await SessionAssembler.buildAndSave(sessionDir: widget.sessionDir);
    final Map<String, dynamic>? data = await SessionService.readJsonIfExists(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.finalSession,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      finalSession = data;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String childName = widget.childInfo['name']?.toString().trim() ?? '';

    final List<dynamic> completedModules =
        finalSession?['completed_modules'] is List
        ? finalSession!['completed_modules'] as List<dynamic>
        : <dynamic>[];

    final Map<String, dynamic> files = finalSession?['files'] is Map
        ? Map<String, dynamic>.from(finalSession!['files'] as Map)
        : <String, dynamic>{};

    final Map<String, dynamic> sessionQuality =
        finalSession?['session_quality'] is Map
        ? Map<String, dynamic>.from(finalSession!['session_quality'] as Map)
        : <String, dynamic>{};

    final String qualityStatus =
        sessionQuality['overall_status']?.toString() ?? 'unknown';

    return Scaffold(
      appBar: AppBar(title: const Text('Session Summary')),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Child: $childName',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      'Session folder:\n${widget.sessionDir.path}',
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Session Quality',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      qualityStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: qualityStatus == 'valid'
                            ? Colors.green
                            : qualityStatus == 'warning'
                            ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Completed Modules',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final dynamic module in completedModules)
                      Text('✓ $module'),
                    const SizedBox(height: 24),
                    const Text(
                      'Generated Files',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final MapEntry<String, dynamic> entry in files.entries)
                      Text(
                        entry.value == true
                            ? '✓ ${entry.key}'
                            : '• ${entry.key}: ${entry.value}',
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Phenotype calculation is intentionally not added yet.',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
