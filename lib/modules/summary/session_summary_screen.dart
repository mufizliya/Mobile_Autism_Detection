import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../session/session_export_service.dart';
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
  SessionExportResult? exportResult;
  bool loading = true;
  bool exporting = false;
  String? exportError;

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

  Future<SessionExportResult?> _createExportZip() async {
    setState(() {
      exporting = true;
      exportError = null;
    });

    try {
      await SessionAssembler.buildAndSave(sessionDir: widget.sessionDir);
      final SessionExportResult result =
          await SessionExportService.createDatasetExportZip(
        sessionDir: widget.sessionDir,
      );

      final Map<String, dynamic>? updatedFinalSession =
          await SessionService.readJsonIfExists(
        sessionDir: widget.sessionDir,
        fileName: SessionFileNames.finalSession,
      );

      if (!mounted) {
        return result;
      }

      setState(() {
        exportResult = result;
        finalSession = updatedFinalSession ?? finalSession;
        exporting = false;
      });

      return result;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      setState(() {
        exportError = error.toString();
        exporting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );

      return null;
    }
  }

  Future<void> _shareExportZip() async {
    final SessionExportResult? result = exportResult ?? await _createExportZip();

    if (!mounted || result == null) {
      return;
    }

    final ShareResult shareResult = await SharePlus.instance.share(
      ShareParams(
        title: 'Autism research session export',
        subject: 'Mobile research session export ZIP',
        text:
            'Research dataset session export. Not for diagnosis or clinical use.',
        files: <XFile>[
          XFile(
            result.zipFile.path,
            name: result.zipFile.uri.pathSegments.last,
            mimeType: 'application/zip',
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share result: ${shareResult.status.name}')),
    );
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
    final Map<String, dynamic> featureReliability =
        finalSession?['feature_reliability'] is Map
        ? Map<String, dynamic>.from(finalSession!['feature_reliability'] as Map)
        : <String, dynamic>{};

    final String overallReliability =
        featureReliability['overall_reliability']?.toString() ?? 'unknown';

    final Map<String, dynamic> mlDatasetExport =
        finalSession?['ml_dataset_export'] is Map
        ? Map<String, dynamic>.from(finalSession!['ml_dataset_export'] as Map)
        : <String, dynamic>{};

    final bool mlRowReady = files[SessionFileNames.mlDatasetRowCsv] == true &&
        files[SessionFileNames.mlDatasetRowJson] == true;

    final Map<String, dynamic> prototypePrediction =
        finalSession?['prototype_model_prediction'] is Map
            ? Map<String, dynamic>.from(
                finalSession!['prototype_model_prediction'] as Map,
              )
            : <String, dynamic>{};

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
                    const SizedBox(height: 8),
                    SelectableText(
                      overallReliability,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 20),
                    _PrototypeModelCard(prediction: prototypePrediction),
                    const SizedBox(height: 16),
                    _ExportCard(
                      mlRowReady: mlRowReady,
                      clinicalUseAllowed:
                          mlDatasetExport['clinical_use_allowed'] == true,
                      exporting: exporting,
                      exportResult: exportResult,
                      exportError: exportError,
                      onCreateZip: _createExportZip,
                      onShareZip: _shareExportZip,
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
                  ],
                ),
              ),
      ),
    );
  }
}

class _PrototypeModelCard extends StatelessWidget {
  const _PrototypeModelCard({required this.prediction});

  final Map<String, dynamic> prediction;

  @override
  Widget build(BuildContext context) {
    final String status = prediction['status']?.toString() ?? 'unavailable';
    final bool computed = status == 'computed';
    final String label = prediction['prototype_prediction']?.toString() ??
        'unavailable';
    final double? probability = _doubleOrNull(
      prediction['autism_probability_prototype'],
    );
    final double? threshold = _doubleOrNull(prediction['threshold']);

    final Color accentColor = !computed
        ? Colors.orange
        : label == 'autism_positive'
            ? Colors.deepOrange
            : Colors.green;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: accentColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Prototype Model Test Result',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (computed) ...[
              Text(
                label == 'autism_positive'
                    ? 'Prototype output: Autism-positive pattern'
                    : 'Prototype output: Autism-negative pattern',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Probability: ${_formatPercent(probability)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('Threshold: ${_formatDecimal(threshold)}'),
              const SizedBox(height: 8),
              Text('Model: ${prediction['model_id'] ?? 'unknown'}'),
              Text(
                'Missing features: ${prediction['missing_feature_count'] ?? 'unknown'}',
              ),
            ] else ...[
              Text(
                'Prototype prediction unavailable',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                prediction['error']?.toString() ??
                    'No prototype prediction was generated yet.',
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Text(
                'Research prototype only. This is not a diagnosis, not a clinical screening result, and not for medical decisions.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double? _doubleOrNull(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String _formatPercent(double? value) {
    if (value == null) {
      return 'unavailable';
    }
    return '${(value * 100).toStringAsFixed(2)}%';
  }

  static String _formatDecimal(double? value) {
    if (value == null) {
      return 'unavailable';
    }
    return value.toStringAsFixed(4);
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.mlRowReady,
    required this.clinicalUseAllowed,
    required this.exporting,
    required this.exportResult,
    required this.exportError,
    required this.onCreateZip,
    required this.onShareZip,
  });

  final bool mlRowReady;
  final bool clinicalUseAllowed;
  final bool exporting;
  final SessionExportResult? exportResult;
  final String? exportError;
  final Future<SessionExportResult?> Function() onCreateZip;
  final Future<void> Function() onShareZip;

  @override
  Widget build(BuildContext context) {
    final SessionExportResult? result = exportResult;
    final Map<String, dynamic>? metadata = result?.metadata;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Dataset Collection Export',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(mlRowReady ? '✓ ML row ready' : '⚠ ML row not ready'),
            Text(
              clinicalUseAllowed
                  ? '⚠ Clinical use flag is enabled'
                  : '✓ Research-only / not diagnostic',
            ),
            const SizedBox(height: 8),
            const Text(
              'The ZIP includes JSON/CSV/SRT/TXT session outputs. Raw video files and older ZIP files are excluded by default.',
            ),
            if (metadata != null) ...<Widget>[
              const SizedBox(height: 10),
              SelectableText(
                'ZIP: ${result!.zipFile.path}\nSize: ${metadata['zip_size_mb']} MB',
              ),
            ],
            if (exportError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                exportError!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 14),
            if (exporting)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              ElevatedButton.icon(
                onPressed: onCreateZip,
                icon: const Icon(Icons.archive),
                label: Text(result == null ? 'Create Export ZIP' : 'Recreate ZIP'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onShareZip,
                icon: const Icon(Icons.share),
                label: const Text('Create & Share Session ZIP'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
