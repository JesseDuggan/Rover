import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class FieldDiagnostics extends ChangeNotifier {
  FieldDiagnostics._();

  static final FieldDiagnostics instance = FieldDiagnostics._();

  static const int _maximumEntries = 12;

  final List<FieldDiagnosticEntry> _entries = [];

  File? _file;

  List<FieldDiagnosticEntry> get entries => List.unmodifiable(_entries);
  FieldDiagnosticEntry? get latest => _entries.isEmpty ? null : _entries.last;

  void record(String area, String message) {
    final entry = FieldDiagnosticEntry(
      area: _sanitize(area),
      message: _sanitize(message),
      recordedAt: DateTime.now(),
    );
    _entries.add(entry);
    if (_entries.length > _maximumEntries) {
      _entries.removeAt(0);
    }
    unawaited(_appendToFile(entry));
    notifyListeners();
  }

  String toRedactedText() {
    return [
      'Rover field diagnostics',
      if (_entries.isEmpty) 'none',
      for (final entry in _entries) entry.summary,
    ].join('\n');
  }

  Future<void> _appendToFile(FieldDiagnosticEntry entry) async {
    if (kIsWeb) {
      return;
    }

    try {
      final file = _file ??= File(
        '${Directory.systemTemp.path}'
        '${Platform.pathSeparator}'
        'rover_field_diagnostics.log',
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('${entry.summary}\n', mode: FileMode.append);
    } catch (_) {
      // Best-effort field logging must never interrupt navigation.
    }
  }

  String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'access_token=[^&\s]+'), 'access_token=<redacted>')
        .replaceAll(RegExp(r'pk\.[A-Za-z0-9._-]+'), 'pk.<redacted>')
        .replaceAll(RegExp(r'sk[_\-.][A-Za-z0-9._-]+'), 'sk.<redacted>')
        .replaceAll(
          RegExp(r'/api/walks/[A-Za-z0-9_-]+', caseSensitive: false),
          '/api/walks/{walkId}',
        )
        .replaceAll(
          RegExp(r'/api/profiles/[A-Za-z0-9_-]+', caseSensitive: false),
          '/api/profiles/{profileId}',
        );
  }
}

class FieldDiagnosticEntry {
  const FieldDiagnosticEntry({
    required this.area,
    required this.message,
    required this.recordedAt,
  });

  final String area;
  final String message;
  final DateTime recordedAt;

  String get summary {
    final time = recordedAt.toIso8601String().split('T').last.split('.').first;
    return '$time $area: $message';
  }
}
