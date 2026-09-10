import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'beta_models.dart';

class OfflineProblemReportQueue {
  OfflineProblemReportQueue({File? file})
    : _file = kIsWeb
          ? null
          : file ??
                File(
                  '${Directory.systemTemp.path}'
                  '${Platform.pathSeparator}'
                  'rover_problem_report_queue.json',
                );

  final File? _file;
  final List<ProblemReportRequest> _webQueue = [];

  Future<void> enqueue(ProblemReportRequest request) async {
    final queued = await load();
    queued.add(request);
    await _save(queued);
  }

  Future<List<ProblemReportRequest>> load() async {
    final file = _file;
    if (file == null) {
      return List<ProblemReportRequest>.from(_webQueue);
    }
    if (!await file.exists()) {
      return [];
    }
    final source = await file.readAsString();
    if (source.trim().isEmpty) {
      return [];
    }
    final decoded = jsonDecode(source) as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(
          (json) => ProblemReportRequest(
            category: json['category'] as String,
            description: json['description'] as String?,
            walkSessionId: json['walkSessionId'] as String?,
            stopId: json['stopId'] as String?,
            correlationId: json['correlationId'] as String?,
            appVersion: json['appVersion'] as String? ?? '1.0.0-beta',
            buildNumber: json['buildNumber'] as String? ?? '9',
            deviceModel: json['deviceModel'] as String? ?? 'Android device',
            osVersion: json['osVersion'] as String? ?? 'Android',
            connectivityState:
                json['connectivityState'] as String? ?? 'offline',
            preciseLocationAttached:
                json['preciseLocationAttached'] as bool? ?? false,
          ),
        )
        .toList();
  }

  Future<void> clear() => _save([]);

  Future<void> _save(List<ProblemReportRequest> requests) async {
    final file = _file;
    if (file == null) {
      _webQueue
        ..clear()
        ..addAll(requests);
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(requests.map((request) => request.toJson()).toList()),
    );
  }
}
