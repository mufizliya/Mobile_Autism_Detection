import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../session/session_file_names.dart';
import '../../session/session_service.dart';
import '../gaze_calibration/gaze_calibration_screen.dart';
import 'scq_data.dart';

class ScqScreen extends StatefulWidget {
  const ScqScreen({
    super.key,
    required this.sessionDir,
    required this.childInfo,
  });

  final Directory sessionDir;
  final Map<String, dynamic> childInfo;

  @override
  State<ScqScreen> createState() => _ScqScreenState();
}

class _ScqScreenState extends State<ScqScreen> {
  final Map<int, String> responses = {};
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    // Python version defaults every question to "Yes".
    for (int i = 0; i < ScqData.questions.length; i++) {
      responses[i] = 'Yes';
    }
  }

  Future<void> submitScq() async {
    setState(() {
      isSaving = true;
    });

    final Map<String, String> answers = {
      for (int i = 0; i < ScqData.questions.length; i++)
        'Q${i + 1}': responses[i] ?? 'Yes',
    };

    final int score = ScqData.calculateScore(answers);

    final String outcome = score >= ScqData.threshold
        ? 'Further evaluation recommended'
        : 'Screening indicates low risk';

    final Map<String, dynamic> phenotypes = ScqData.calculatePhenotypes(
      answers,
    );

    final String timestamp = DateTime.now().toIso8601String();

    final Map<String, dynamic> record = {
      'timestamp': timestamp,
      'name': widget.childInfo['name'],
      'age': widget.childInfo['age'],
      'gender': widget.childInfo['gender'],
      'scq_score': score,
      'outcome': outcome,
      'phenotypes': phenotypes,

      // Python saves answers as json.dumps(answers), so we keep the same style.
      'answers': jsonEncode(answers),
    };

    await SessionService.saveJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.scqResults,
      data: record,
    );

    await SessionService.updateJson(
      sessionDir: widget.sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: {
        'updated_at': timestamp,
        'completed_modules': ['child_info', 'scq'],
        'files': {
          SessionFileNames.childInfo: true,
          SessionFileNames.scqResults: true,
        },
        'scq_results': record,
      },
    );

    if (!mounted) return;

    setState(() {
      isSaving = false;
    });

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('SCQ Result'),
          content: Text('Score: $score\nOutcome: $outcome'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return GazeCalibrationScreen(
            sessionDir: widget.sessionDir,
            childInfo: widget.childInfo,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.childInfo['name']?.toString() ?? '';
    final String age = widget.childInfo['age']?.toString() ?? '';
    final String gender = widget.childInfo['gender']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Social Communication Questionnaire')),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                'Child: $name | Age: $age | Gender: $gender',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: ScqData.questions.length,
                itemBuilder: (BuildContext context, int index) {
                  final int questionNumber = index + 1;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Q$questionNumber. ${ScqData.questions[index]}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          RadioGroup<String>(
                            groupValue: responses[index],
                            onChanged: (String? value) {
                              if (isSaving) {
                                return;
                              }

                              setState(() {
                                responses[index] = value ?? 'Yes';
                              });
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () {
                                            setState(() {
                                              responses[index] = 'Yes';
                                            });
                                          },
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Row(
                                      children: [
                                        Radio<String>(value: 'Yes'),
                                        Text('Yes'),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () {
                                            setState(() {
                                              responses[index] = 'No';
                                            });
                                          },
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Row(
                                      children: [
                                        Radio<String>(value: 'No'),
                                        Text('No'),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSaving ? null : submitScq,
                  child: isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit SCQ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
