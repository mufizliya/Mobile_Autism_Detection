import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'session_file_names.dart';
import 'session_service.dart';

class SessionExportResult {
  const SessionExportResult({
    required this.zipFile,
    required this.metadata,
  });

  final File zipFile;
  final Map<String, dynamic> metadata;
}

class SessionExportService {
  static const Set<String> _allowedExtensions = <String>{
    '.json',
    '.csv',
    '.srt',
    '.txt',
  };

  static const Set<String> _blockedExtensions = <String>{
    '.zip',
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
  };

  static Future<Directory> getExportsRootDir() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();
    final Directory exportsDir = Directory('${docsDir.path}/session_exports');

    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    return exportsDir;
  }

  static Future<SessionExportResult> createDatasetExportZip({
    required Directory sessionDir,
  }) async {
    if (!await sessionDir.exists()) {
      throw StateError('Session folder does not exist: ${sessionDir.path}');
    }

    final String sessionName = _lastPathSegment(sessionDir.path);
    final Directory exportsRoot = await getExportsRootDir();
    final File zipFile = File('${exportsRoot.path}/${sessionName}_export.zip');

    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final List<File> exportableFiles = await _collectExportableFiles(sessionDir);
    final List<String> includedFiles = exportableFiles
        .map((File file) => _relativePath(sessionDir, file))
        .toList()
      ..sort();

    final Map<String, dynamic>? finalSession =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
    );

    final Map<String, dynamic>? mlDatasetRow =
        await SessionService.readJsonIfExists(
      sessionDir: sessionDir,
      fileName: SessionFileNames.mlDatasetRowJson,
    );

    final Map<String, dynamic> metadata = <String, dynamic>{
      'schema_version': 'mobile_dataset_session_export_v1',
      'created_at': DateTime.now().toIso8601String(),
      'session_dir': sessionDir.path,
      'session_folder_name': sessionName,
      'zip_file_name': zipFile.uri.pathSegments.last,
      'zip_path': zipFile.path,
      'export_purpose': 'research_dataset_collection',
      'clinical_use_allowed': false,
      'diagnosis_generated': false,
      'privacy_note':
          'This export intentionally includes numeric JSON/CSV/session files only. Raw videos and archive files are excluded by default.',
      'included_file_count': includedFiles.length + 1,
      'included_files': <String>[
        ...includedFiles,
        SessionFileNames.sessionExportMetadata,
      ]..sort(),
      'excluded_by_default': <String>[
        '*.zip',
        '*.mp4',
        '*.mov',
        '*.avi',
        '*.mkv',
        '*.webm',
      ],
      'session_quality': finalSession?['session_quality'],
      'feature_reliability': finalSession?['feature_reliability'],
      'ml_dataset_row_available': mlDatasetRow != null,
      'ml_dataset_files': <String, dynamic>{
        SessionFileNames.mlDatasetRowJson: includedFiles.contains(
          SessionFileNames.mlDatasetRowJson,
        ),
        SessionFileNames.mlDatasetRowCsv: includedFiles.contains(
          SessionFileNames.mlDatasetRowCsv,
        ),
        SessionFileNames.mlDatasetSchema: includedFiles.contains(
          SessionFileNames.mlDatasetSchema,
        ),
      },
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.sessionExportMetadata,
      data: metadata,
    );

    await SessionService.updateJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.finalSession,
      updates: <String, dynamic>{
        'session_export': <String, dynamic>{
          'schema_version': 'mobile_dataset_session_export_reference_v1',
          'status': 'ready_to_share',
          'zip_file_name': zipFile.uri.pathSegments.last,
          'zip_path': zipFile.path,
          'metadata_file': SessionFileNames.sessionExportMetadata,
          'clinical_use_allowed': false,
          'raw_video_included': false,
        },
      },
    );

    await _writeZip(
      sessionDir: sessionDir,
      zipFile: zipFile,
      sessionName: sessionName,
    );

    final int sizeBytes = await zipFile.length();
    final Map<String, dynamic> finalizedMetadata = <String, dynamic>{
      ...metadata,
      'zip_exists': await zipFile.exists(),
      'zip_size_bytes': sizeBytes,
      'zip_size_mb': double.parse(
        (sizeBytes / (1024 * 1024)).toStringAsFixed(3),
      ),
    };

    await SessionService.saveJson(
      sessionDir: sessionDir,
      fileName: SessionFileNames.sessionExportMetadata,
      data: finalizedMetadata,
    );

    return SessionExportResult(
      zipFile: zipFile,
      metadata: finalizedMetadata,
    );
  }

  static Future<List<File>> _collectExportableFiles(Directory sessionDir) async {
    final List<File> files = <File>[];

    await for (final FileSystemEntity entity in sessionDir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }

      final String fileName = _lastPathSegment(entity.path);
      if (fileName.startsWith('.')) {
        continue;
      }

      final String extension = _extension(fileName);
      if (_blockedExtensions.contains(extension)) {
        continue;
      }

      if (!_allowedExtensions.contains(extension)) {
        continue;
      }

      files.add(entity);
    }

    files.sort(
      (File a, File b) => _relativePath(sessionDir, a).compareTo(
        _relativePath(sessionDir, b),
      ),
    );

    return files;
  }

  static Future<void> _writeZip({
    required Directory sessionDir,
    required File zipFile,
    required String sessionName,
  }) async {
    final ZipFileEncoder encoder = ZipFileEncoder();
    encoder.create(zipFile.path);

    try {
      final List<File> files = await _collectExportableFiles(sessionDir);
      for (final File file in files) {
        final String relative = _relativePath(sessionDir, file);
        final String archiveName = '$sessionName/$relative'.replaceAll('\\', '/');
        await encoder.addFile(file, archiveName);
      }
    } finally {
      await encoder.close();
    }
  }

  static String _relativePath(Directory root, File file) {
    final String rootPath = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';

    String relative = file.path.startsWith(rootPath)
        ? file.path.substring(rootPath.length)
        : _lastPathSegment(file.path);

    return relative.replaceAll('\\', '/');
  }

  static String _lastPathSegment(String path) {
    final List<String> parts = path
        .split(RegExp(r'[\\/]'))
        .where((String part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'session';
    }

    return parts.last;
  }

  static String _extension(String fileName) {
    final int dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) {
      return '';
    }
    return fileName.substring(dotIndex).toLowerCase();
  }
}
