import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SessionService {
  static Future<Directory> getSessionsRootDir() async {
    final Directory docsDir = await getApplicationDocumentsDirectory();

    final Directory sessionsDir = Directory(
      '${docsDir.path}/sessions',
    );

    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }

    return sessionsDir;
  }

  static Future<Directory> createSessionDir() async {
    final Directory root = await getSessionsRootDir();

    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    final Directory sessionDir = Directory(
      '${root.path}/session_$timestamp',
    );

    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    return sessionDir;
  }

  static File fileInSession({
    required Directory sessionDir,
    required String fileName,
  }) {
    return File('${sessionDir.path}/$fileName');
  }

  static Future<void> saveJson({
    required Directory sessionDir,
    required String fileName,
    required Map<String, dynamic> data,
  }) async {
    final File file = fileInSession(
      sessionDir: sessionDir,
      fileName: fileName,
    );

    const JsonEncoder encoder = JsonEncoder.withIndent('  ');

    await file.writeAsString(
      encoder.convert(data),
      flush: true,
    );
  }

  static Future<Map<String, dynamic>?> readJsonIfExists({
    required Directory sessionDir,
    required String fileName,
  }) async {
    final File file = fileInSession(
      sessionDir: sessionDir,
      fileName: fileName,
    );

    if (!await file.exists()) {
      return null;
    }

    final String raw = await file.readAsString();

    if (raw.trim().isEmpty) {
      return null;
    }

    final dynamic decoded = jsonDecode(raw);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return null;
  }

  static Future<void> updateJson({
    required Directory sessionDir,
    required String fileName,
    required Map<String, dynamic> updates,
  }) async {
    final Map<String, dynamic> existing =
        await readJsonIfExists(
              sessionDir: sessionDir,
              fileName: fileName,
            ) ??
            <String, dynamic>{};

    existing.addAll(updates);

    await saveJson(
      sessionDir: sessionDir,
      fileName: fileName,
      data: existing,
    );
  }

  static Future<void> saveCsv({
    required Directory sessionDir,
    required String fileName,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final File file = fileInSession(
      sessionDir: sessionDir,
      fileName: fileName,
    );

    final StringBuffer buffer = StringBuffer();

    buffer.writeln(
      headers.map(_escapeCsvCell).join(','),
    );

    for (final List<dynamic> row in rows) {
      buffer.writeln(
        row.map(_escapeCsvCell).join(','),
      );
    }

    await file.writeAsString(
      buffer.toString(),
      flush: true,
    );
  }

  static Future<void> appendCsvRow({
    required Directory sessionDir,
    required String fileName,
    required List<String> headers,
    required List<dynamic> row,
  }) async {
    final File file = fileInSession(
      sessionDir: sessionDir,
      fileName: fileName,
    );

    if (!await file.exists()) {
      await file.writeAsString(
        '${headers.map(_escapeCsvCell).join(',')}\n',
        flush: true,
      );
    }

    await file.writeAsString(
      '${row.map(_escapeCsvCell).join(',')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static String _escapeCsvCell(dynamic value) {
    if (value == null) {
      return '';
    }

    final String text = value.toString();

    final bool needsQuotes =
        text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');

    if (!needsQuotes) {
      return text;
    }

    return '"${text.replaceAll('"', '""')}"';
  }
}