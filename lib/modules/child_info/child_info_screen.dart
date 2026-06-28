import 'dart:io';

import 'package:flutter/material.dart';

import '../../modules/scq/scq_screen.dart';
import '../../session/session_file_names.dart';
import '../../session/session_service.dart';

class ChildInfoScreen extends StatefulWidget {
  const ChildInfoScreen({super.key});

  @override
  State<ChildInfoScreen> createState() => _ChildInfoScreenState();
}

class _ChildInfoScreenState extends State<ChildInfoScreen> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();

  String selectedGender = 'Male';
  bool isSaving = false;

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    super.dispose();
  }

  Future<void> saveAndContinue() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final String timestamp = DateTime.now().toIso8601String();

    final Map<String, dynamic> childInfo = {
      'name': nameController.text.trim(),
      'age': ageController.text.trim(),
      'gender': selectedGender,
      'timestamp': timestamp,
    };

    final Directory sessionDir = await SessionService.createSessionDir();

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.childInfo,
      data: childInfo,
    );

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
      data: {
        'created_at': timestamp,
        'updated_at': timestamp,
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

    if (!mounted) return;

    setState(() {
      isSaving = false;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return ScqScreen(
            sessionDir: sessionDir,
            childInfo: childInfo,
          );
        },
      ),
    );
  }

  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the child name';
    }

    return null;
  }

  String? validateAge(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter age';
    }

    final int? parsed = int.tryParse(value.trim());

    if (parsed == null) {
      return 'Enter a number';
    }

    if (parsed < 2 || parsed > 18) {
      return 'Python app range is 2 to 18';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Information Entry'),
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
                  'Child Information Entry',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 24),

                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter full name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: validateName,
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: ageController,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: validateAge,
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: selectedGender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Male',
                      child: Text('Male'),
                    ),
                    DropdownMenuItem(
                      value: 'Female',
                      child: Text('Female'),
                    ),
                    DropdownMenuItem(
                      value: 'Other',
                      child: Text('Other'),
                    ),
                  ],
                  onChanged: isSaving
                      ? null
                      : (String? value) {
                          setState(() {
                            selectedGender = value ?? 'Male';
                          });
                        },
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: isSaving ? null : saveAndContinue,
                  child: isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Submit Information'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}