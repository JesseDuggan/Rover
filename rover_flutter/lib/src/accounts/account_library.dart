import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/rover_api_config.dart';
import '../preferences/rover_preferences.dart';

class LibraryException implements Exception {
  const LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.name,
    required this.data,
    required this.revision,
    this.isDefault = false,
  });
  final String id;
  final String name;
  final Map<String, dynamic> data;
  final int revision;
  final bool isDefault;
  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
    id: json['id'] as String,
    name: json['name'] as String,
    data: json['data'] as Map<String, dynamic>,
    revision: json['revision'] as int,
    isDefault: json['isDefault'] == true,
  );
}

const walkingProfileFields = <String>{
  'interests',
  'walkingPace',
  'availableTime',
  'mobility',
  'contentDepth',
  'includePaidAttractions',
  'storyDensity',
  'excludedStoryCategories',
  'audioPreference',
  'distanceUnit',
  'language',
};

Map<String, dynamic> walkingProfileData(RoverPreferences preferences) =>
    Map.fromEntries(
      preferences.toMap().entries.where(
        (e) => walkingProfileFields.contains(e.key),
      ),
    );

RoverPreferences applyWalkingProfile(
  RoverPreferences current,
  Map<String, dynamic> data,
) => RoverPreferences.fromMap({
  ...current.toMap(),
  ...Map.fromEntries(
    data.entries.where((e) => walkingProfileFields.contains(e.key)),
  ),
});

String newLibraryId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class AccountLibrary extends ChangeNotifier {
  AccountLibrary({
    RoverApiConfig? config,
    FlutterAppAuth? auth,
    FlutterSecureStorage? storage,
  }) : _config = config ?? RoverApiConfig.fromEnvironment(),
       _auth = auth ?? const FlutterAppAuth(),
       _storage = storage ?? const FlutterSecureStorage();
  static final instance = AccountLibrary();
  final RoverApiConfig _config;
  final FlutterAppAuth _auth;
  final FlutterSecureStorage _storage;
  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _tokens;
  Future<void>? _loading;
  Future<String>? _refreshing;
  Future<void> _tokenWrites = Future<void>.value();
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;
  bool get signedIn => _tokens != null;
  bool get enabled => _settings?['enabled'] == true;
  String get publicBaseUrl => Uri.parse(_config.configuredBaseUrl).origin;
  int get profileLimit => (_settings?['profileLimit'] as int?) ?? 3;
  int get walkLimit => (_settings?['walkLimit'] as int?) ?? 3;
  String get _storageKey =>
      'walkabout.account.${Uri.parse(_config.configuredBaseUrl).origin}';
  String get _issuer => _settings!['issuer'] as String;
  String get _clientId => _settings!['clientId'] as String;
  String get _redirect => _settings!['redirectUri'] as String;
  String get _discovery => '$_issuer/.well-known/openid-configuration';

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    final generation = _sessionGeneration;
    _settings = await request(
      'GET',
      '/api/account-library/config',
      authenticated: false,
    ) as Map<String, dynamic>;
    if (!enabled) {
      _tokens = null;
      notifyListeners();
      return;
    }
    final issuer = Uri.tryParse(_issuer);
    if (issuer == null ||
        issuer.scheme != 'https' ||
        !issuer.host.startsWith('cognito-idp.') ||
        !(issuer.host.endsWith('.amazonaws.com') ||
            issuer.host.endsWith('.amazonaws.com.cn')) ||
        _redirect != 'ai.myrover.rover://oauthredirect') {
      throw const LibraryException(
        'Account configuration is invalid. Please contact support.',
      );
    }
    await _tokenWrites;
    final saved = await _storage.read(key: _storageKey);
    if (generation != _sessionGeneration) return;
    _tokens = null;
    if (saved != null) {
      try {
        final tokens = jsonDecode(saved) as Map<String, dynamic>;
        if (tokens['issuer'] == _issuer &&
            tokens['clientId'] == _clientId &&
            tokens['accessToken'] is String &&
            tokens['expiresAt'] is String &&
            DateTime.tryParse(tokens['expiresAt'] as String) != null) {
          _tokens = tokens;
        } else {
          _tokens = null;
          await _storage.delete(key: _storageKey);
        }
      } on FormatException {
        await _storage.delete(key: _storageKey);
      }
    }
    notifyListeners();
  }

  Future<bool> signIn() async {
    await load();
    if (!enabled) {
      throw const LibraryException(
        'Account sign-in has not been enabled on the server yet.',
      );
    }
    try {
      final generation = ++_sessionGeneration;
      final result = await _auth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirect,
          discoveryUrl: _discovery,
          scopes: const ['openid', 'email'],
          promptValues: const ['login'],
        ),
      );
      await _saveTokens(result, generation);
      return true;
    } on FlutterAppAuthUserCancelledException {
      return false;
    }
  }

  Future<void> _saveTokens(
    TokenResponse result,
    int generation, {
    String? previousRefreshToken,
  }) async {
    if (result.accessToken == null ||
        result.accessTokenExpirationDateTime == null) {
      throw const LibraryException('Sign-in did not return a valid session.');
    }
    final tokens = <String, dynamic>{
      'issuer': _issuer,
      'clientId': _clientId,
      'accessToken': result.accessToken,
      'refreshToken': result.refreshToken ?? previousRefreshToken,
      'expiresAt': result.accessTokenExpirationDateTime!
          .toUtc()
          .toIso8601String(),
    };
    _tokenWrites = _tokenWrites.catchError((Object _) {}).then((_) async {
      if (generation != _sessionGeneration) return;
      await _storage.write(key: _storageKey, value: jsonEncode(tokens));
      if (generation == _sessionGeneration) {
        _tokens = tokens;
        notifyListeners();
      }
    });
    await _tokenWrites;
    if (generation != _sessionGeneration) {
      throw const LibraryException(
        'The account session changed. Please try again.',
      );
    }
  }

  Future<String> _accessToken() async {
    if (_tokens == null) {
      throw const LibraryException('Sign in to use your library.');
    }
    final expiry = DateTime.parse(_tokens!['expiresAt'] as String);
    if (expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return _tokens!['accessToken'] as String;
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final generation = _sessionGeneration;
    final refreshToken = _tokens?['refreshToken'] as String?;
    if (refreshToken == null) {
      await signOut();
      throw const LibraryException('Please sign in again.');
    }
    final result = await _auth.token(
      TokenRequest(
        _clientId,
        _redirect,
        discoveryUrl: _discovery,
        refreshToken: refreshToken,
      ),
    );
    await _saveTokens(result, generation, previousRefreshToken: refreshToken);
    return _tokens!['accessToken'] as String;
  }

  Future<void> signOut() async {
    // No account data is cached in shared files. The next sign-in requires interactive login.
    _sessionGeneration++;
    _tokens = null;
    notifyListeners();
    _tokenWrites = _tokenWrites
        .catchError((Object _) {})
        .then((_) => _storage.delete(key: _storageKey));
    await _tokenWrites;
  }

  Future<void> rememberGuest(RoverPreferences preferences) async {
    if (await _storage.read(key: '$_storageKey.guest') == null) {
      await _storage.write(
        key: '$_storageKey.guest',
        value: preferences.toJson(),
      );
    }
  }

  Future<RoverPreferences?> guestPreferences() async {
    final raw = await _storage.read(key: '$_storageKey.guest');
    return raw == null ? null : RoverPreferences.fromJson(raw);
  }

  Future<void> clearGuestBackup() => _storage.delete(key: '$_storageKey.guest');

  Future<List<LibraryItem>> list(String kind) async =>
      (await request('GET', '/api/account-library/$kind') as List<dynamic>)
          .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
          .toList();
  Future<void> save(
    String kind,
    String id,
    String name,
    Map<String, dynamic> data, {
    int revision = 0,
    bool isDefault = false,
  }) async {
    await request(
      'PUT',
      '/api/account-library/$kind/$id',
      body: {
        'name': name,
        'data': data,
        'revision': revision,
        'isDefault': isDefault,
      },
    );
  }

  Future<void> delete(String kind, LibraryItem item) async {
    await request(
      'DELETE',
      '/api/account-library/$kind/${item.id}?revision=${item.revision}',
    );
  }

  Future<void> transferSharedMedia(
    String method,
    String path, {
    File? upload,
    File? download,
  }) async {
    final base = Uri.parse(
      RoverApiConfig.normalizeBaseUrl(_config.configuredBaseUrl),
    );
    final uri = base.resolve(path);
    if (base.scheme != 'https' ||
        uri.origin != base.origin ||
        !RegExp(r'^/api/shared-walks/[a-f0-9]{32}/media/[a-f0-9]{32}$')
            .hasMatch(uri.path) ||
        !((method == 'PUT' && upload != null) ||
            (method == 'GET' && download != null))) {
      throw const LibraryException('Invalid media destination.');
    }
    final generation = sessionGeneration;
    final token = await _accessToken();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    void checkSession() {
      if (!signedIn || generation != sessionGeneration) {
        client.close(force: true);
      }
    }

    addListener(checkSession);
    IOSink? sink;
    var complete = false;
    try {
      if (!signedIn || generation != sessionGeneration) {
        throw const LibraryException('Account changed.');
      }
      final req = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 30));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final beta = _config.betaKeyFor(uri);
      if (beta != null) req.headers.set('X-Rover-Beta-Key', beta);
      if (upload != null) {
        final length = await upload.length();
        if (length == 0 || length > 64 * 1024 * 1024) {
          throw const LibraryException(
            'This memory exceeds the 64 MB sharing limit.',
          );
        }
        req.contentLength = length;
        req.headers.contentType = ContentType.binary;
        await req
            .addStream(upload.openRead())
            .timeout(const Duration(minutes: 3));
      }
      final response = await req.close().timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bytes = <int>[];
        await for (final part in response.timeout(
          const Duration(seconds: 30),
        )) {
          bytes.addAll(part);
          if (bytes.length > 16384) break;
        }
        String? title;
        try {
          title =
              (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['title']
                  as String?;
        } catch (_) {}
        throw LibraryException(
          title != null && title.length < 300
              ? title
              : 'Memory unavailable or access removed. Please refresh.',
        );
      }
      if (download != null) sink = download.openWrite();
      var size = 0;
      await for (final part in response.timeout(const Duration(seconds: 30))) {
        size += part.length;
        if (size > 64 * 1024 * 1024) {
          throw const LibraryException('Memory download is too large.');
        }
        sink?.add(part);
      }
      if (!signedIn || generation != sessionGeneration) {
        throw const LibraryException('Account changed.');
      }
      complete = true;
    } finally {
      removeListener(checkSession);
      client.close(force: true);
      await sink?.close();
      if (!complete && download != null && await download.exists()) {
        await download.delete();
      }
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    // Account credentials are never sent to a development URL override or a redirected host.
    final base = Uri.parse(
      RoverApiConfig.normalizeBaseUrl(_config.configuredBaseUrl),
    );
    if (base.scheme != 'https') {
      throw const LibraryException(
        'Accounts require a secure HTTPS API connection.',
      );
    }
    final uri = base.resolve(path);
    if (uri.origin != base.origin || !uri.path.startsWith('/api/')) {
      throw const LibraryException('Invalid API destination.');
    }
    final token = authenticated ? await _accessToken() : null;
    final client = HttpClient()..connectionTimeout = _config.connectionTimeout;
    try {
      final req = await client
          .openUrl(method, uri)
          .timeout(_config.responseTimeout);
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      final beta = _config.betaKeyFor(uri);
      if (beta != null) req.headers.set('X-Rover-Beta-Key', beta);
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) req.write(jsonEncode(body));
      final response = await req.close().timeout(_config.responseTimeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(_config.responseTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 8_000_000) {
          throw const LibraryException('The server response is too large.');
        }
      }
      if (response.statusCode == 401) {
        throw const LibraryException(
          'Your session or beta access has expired. Please sign in again.',
        );
      }
      if (path.startsWith('/api/shared-walks') &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        String? title;
        try {
          title =
              (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['title']
                  as String?;
        } catch (_) {}
        throw LibraryException(
          title != null && title.length <= 300
              ? title
              : 'Shared walk unavailable. Please refresh or sign in again.',
        );
      }
      if (path.startsWith('/api/friends') &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        if (response.statusCode == 404) {
          throw LibraryException(
            path.contains('/state')
                ? 'Friends is not available on this server yet.'
                : 'Member or invitation unavailable. Check the username or invitation.',
          );
        }
        String? title;
        try {
          title =
              (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['title']
                  as String?;
        } catch (_) {}
        throw LibraryException(
          title != null && title.length <= 300
              ? title
              : 'Could not update friends. Please try again.',
        );
      }
      if (response.statusCode == 409) {
        throw const LibraryException(
          'The item changed or your library is full. Refresh before trying again.',
        );
      }
      if (response.statusCode == 404 && path == '/api/account-library/config') {
        throw const LibraryException(
          'The account service is unavailable on this server. '
          'Please update the server deployment and try again. '
          'This does not mean your Cognito account is missing.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LibraryException(
          'The request could not be completed (${response.statusCode}).',
        );
      }
      return bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } finally {
      client.close(force: true);
    }
  }
}
