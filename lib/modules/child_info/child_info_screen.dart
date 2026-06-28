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
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController childNameController = TextEditingController();
  final TextEditingController ageYearsController = TextEditingController();
  final TextEditingController ageMonthsController = TextEditingController();

  bool isSaving = false;
  Directory? createdSessionDir;

  @override
  void dispose() {
    childNameController.dispose();
    ageYearsController.dispose();
    ageMonthsController.dispose();
    super.dispose();
  }

  Future<void> saveChildInfo() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final String childName = childNameController.text.trim();

    final int ageYears = int.parse(
      ageYearsController.text.trim(),
    );

    final int ageMonthsExtra = int.parse(
      ageMonthsController.text.trim(),
    );

    final int totalAgeMonths = (ageYears * 12) + ageMonthsExtra;

    final Directory sessionDir = await SessionService.createSessionDir();

    final String generatedAt = DateTime.now().toIso8601String();

    final Map<String, dynamic> childInfo = {
      'schema_version': 'python_mobile_replica_child_info_v1',
      'generated_at': generatedAt,
      'child_name': childName,
      'age_years': ageYears,
      'age_months_extra': ageMonthsExtra,
      'age_months_total': totalAgeMonths,
      'source': 'mobile_replica',
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.childInfo,
      data: childInfo,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
      data: {
        'schema_version': 'python_mobile_replica_final_session_v1',
        'created_at': generatedAt,
        'updated_at': generatedAt,
        'session_dir': sessionDir.path,
        'completed_modules': [
          'child_info',
        ],
        'files': {
          SessionFileNames.childInfo: true,
        },
        'child_info': childInfo,
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      isSaving = false;
      createdSessionDir = sessionDir;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Child info saved. Session created.'),
      ),
    );
  }

  String? validateRequiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? validateAgeYears(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final int? parsed = int.tryParse(value.trim());

    if (parsed == null) {
      return 'Enter a number';
    }

    if (parsed < 0 || parsed > 10) {
      return 'Enter age years between 0 and 10';
    }

    return null;
  }

  String? validateAgeMonths(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final int? parsed = int.tryParse(value.trim());

    if (parsed == null) {
      return 'Enter a number';
    }

    if (parsed < 0 || parsed > 11) {
      return 'Enter extra months between 0 and 11';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSession = createdSessionDir != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Information'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter child details',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This creates the session folder and saves child_info.json.',
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: childNameController,
                  decoration: const InputDecoration(
                    labelText: 'Child name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: validateRequiredText,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: ageYearsController,
                  decoration: const InputDecoration(
                    labelText: 'Age - years',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: validateAgeYears,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: ageMonthsController,
                  decoration: const InputDecoration(
                    labelText: 'Extra months',
                    helperText: 'Example: 2 years 6 months → years = 2, months = 6',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: validateAgeMonths,
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: isSaving ? null : saveChildInfo,
                  child: isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save and create session'),
                ),

                const SizedBox(height: 24),

                if (hasSession)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        'Session created:\n${createdSessionDir!.path}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}