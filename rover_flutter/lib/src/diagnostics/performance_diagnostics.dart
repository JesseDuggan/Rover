import 'package:flutter/foundation.dart';

class PerformanceDiagnostics extends ChangeNotifier {
  PerformanceDiagnostics._();

  static final PerformanceDiagnostics instance = PerformanceDiagnostics._();

  static const int _maximumSamples = 8;
  static const int slowOperationThresholdMs = 750;

  final List<PerformanceSample> _slowOperations = [];
  PerformanceSample? _lastOperation;
  PerformanceSample? _lastSlowOperation;

  PerformanceSample? get lastOperation => _lastOperation;
  PerformanceSample? get lastSlowOperation => _lastSlowOperation;
  List<PerformanceSample> get slowOperations =>
      List.unmodifiable(_slowOperations);

  void record(String name, Duration elapsed, {bool success = true}) {
    final sample = PerformanceSample(
      name: _sanitize(name),
      elapsedMilliseconds: elapsed.inMilliseconds,
      success: success,
      recordedAt: DateTime.now(),
    );
    _lastOperation = sample;
    if (sample.elapsedMilliseconds >= slowOperationThresholdMs) {
      _lastSlowOperation = sample;
      _slowOperations.add(sample);
      if (_slowOperations.length > _maximumSamples) {
        _slowOperations.removeAt(0);
      }
    }
    notifyListeners();
  }

  String toRedactedText() {
    return [
      'Rover Flutter performance',
      'last operation: ${_lastOperation?.summary ?? 'none'}',
      'last slow operation: ${_lastSlowOperation?.summary ?? 'none'}',
      if (_slowOperations.isNotEmpty) 'recent slow operations:',
      for (final sample in _slowOperations) sample.summary,
    ].join('\n');
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
        )
        .replaceAll(RegExp(r'\?.*'), '?<query>');
  }
}

class PerformanceSample {
  const PerformanceSample({
    required this.name,
    required this.elapsedMilliseconds,
    required this.success,
    required this.recordedAt,
  });

  final String name;
  final int elapsedMilliseconds;
  final bool success;
  final DateTime recordedAt;

  String get summary =>
      '$name: $elapsedMilliseconds ms, ${success ? 'ok' : 'failed'}';
}
