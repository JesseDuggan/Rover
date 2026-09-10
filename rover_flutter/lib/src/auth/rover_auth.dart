class RoverAuthSession {
  const RoverAuthSession({
    required this.provider,
    required this.subject,
    required this.accessToken,
    required this.expiresAtUtc,
    this.refreshToken,
    this.email,
  });

  final String provider;
  final String subject;
  final String accessToken;
  final DateTime expiresAtUtc;
  final String? refreshToken;
  final String? email;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAtUtc);
}

abstract class SecureTokenStore {
  Future<RoverAuthSession?> load();
  Future<void> save(RoverAuthSession session);
  Future<void> clear();
}

abstract class RoverAuthProvider {
  Future<RoverAuthSession> createAccount();
  Future<RoverAuthSession> signIn();
  Future<RoverAuthSession?> restore();
  Future<RoverAuthSession> refresh(RoverAuthSession session);
  Future<void> signOut(RoverAuthSession? session);
  Future<void> forgotPassword(String email);
  Future<void> verifyEmail(String email, String code);
}

class InMemorySecureTokenStore implements SecureTokenStore {
  RoverAuthSession? _session;

  @override
  Future<RoverAuthSession?> load() async => _session;

  @override
  Future<void> save(RoverAuthSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
