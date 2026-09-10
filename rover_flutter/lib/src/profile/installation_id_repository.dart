import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class InstallationIdRepository {
  InstallationIdRepository({File? file})
    : _file = kIsWeb
          ? null
          : file ??
                File(
                  '${Directory.systemTemp.path}'
                  '${Platform.pathSeparator}'
                  'rover_installation_id.txt',
                );

  final File? _file;
  String? _webInstallationId;

  Future<String> loadOrCreate() async {
    final file = _file;
    if (file == null) {
      return _webInstallationId ??= _newInstallationId();
    }

    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }

    final value = _newInstallationId();
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
    return value;
  }

  String _newInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
