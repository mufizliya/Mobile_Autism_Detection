import 'dart:io';

import 'package:flutter/material.dart';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';

class ChildInfoScreen extends StatefulWidget {
  const ChildInfoScreen({super.key});

  @override
  State<ChildInfoScreen> createState() => _ChildInfoScreenState();
}

class _ChildInfoScreenState extends State<ChildInfoScreen> {
  Directory? sessionDir;
  String status = 'No session created yet.';

  Future<void> createTestSession() async {
    final Directory newSessionDir = await SessionService.createSessionDir();

    await SessionService.saveJson(
      sessionDir: newSessionDir,
      fileName: SessionFileNames.childInfo,
      data: {
        'schema_version': 'python_mobile_replica_child_info_v1',
        'generated_at': DateTime.now().toIso8601String(),
        'child_name': 'Test Child',
        'age_years': 0,
        'source': 'mobile_replica_test',
      },
    );

    await SessionService.updateJson(
      sessionDir: newSessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'schema_version': 'python_mobile_replica_final_session_v1',
        'created_at': DateTime.now().toIso8601String(),
        'session_dir': newSessionDir.path,
        'completed_modules': [
          'child_info_test',
        ],
      },
    );

    if (!mounted) return;

    setState(() {
      sessionDir = newSessionDir;
      status = 'Created session:\n${newSessionDir.path}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Replica - Step 1'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Fresh mobile replica started.',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This first step only tests session folder creation and JSON writing.',
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: createTestSession,
              child: const Text('Create test session'),
            ),
            const SizedBox(height: 24),
            SelectableText(status),
          ],
        ),
      ),
    );
  }
}