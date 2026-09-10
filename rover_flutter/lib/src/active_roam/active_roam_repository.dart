import 'dart:io';

import 'package:flutter/foundation.dart';

import 'active_roam_session.dart';

abstract class ActiveRoamRepository {
  Future<RoamSession?> load();
  Future<void> save(RoamSession session);
  Future<void> reset();
}

class FileActiveRoamRepository implements ActiveRoamRepository {
  FileActiveRoamRepository({File? file})
    : _file = kIsWeb
          ? null
          : file ??
                File(
                  '${Directory.systemTemp.path}'
                  '${Platform.pathSeparator}'
                  'rover_active_roam.json',
                );

  final File? _file;
  RoamSession? _webSession;

  @override
  Future<RoamSession?> load() async {
    final file = _file;
    if (file == null) {
      return _webSession;
    }
    if (!await file.exists()) {
      return null;
    }
    final source = await file.readAsString();
    return source.trim().isEmpty ? null : RoamSession.fromJson(source);
  }

  @override
  Future<void> reset() async {
    final file = _file;
    if (file == null) {
      _webSession = null;
      return;
    }
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> save(RoamSession session) async {
    final file = _file;
    if (file == null) {
      _webSession = session;
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(session.toJson());
  }
}

class MemoryActiveRoamRepository implements ActiveRoamRepository {
  MemoryActiveRoamRepository([this._session]);

  RoamSession? _session;

  @override
  Future<RoamSession?> load() async => _session;

  @override
  Future<void> reset() async {
    _session = null;
  }

  @override
  Future<void> save(RoamSession session) async {
    _session = session;
  }
}
