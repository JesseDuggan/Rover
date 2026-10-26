class Member {
  const Member({
    required this.id,
    required this.username,
    required this.displayName,
  });
  final String id, username, displayName;
  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
  );
}

class FriendConnection {
  const FriendConnection({
    required this.member,
    required this.status,
    this.requestId,
  });
  final Member member;
  final String status;
  final String? requestId;
  factory FriendConnection.fromJson(Map<String, dynamic> json) =>
      FriendConnection(
        member: Member.fromJson(json['member'] as Map<String, dynamic>),
        status: json['status'] as String,
        requestId: json['requestId'] as String?,
      );
}

class FriendsSnapshot {
  const FriendsSnapshot({
    this.profile,
    this.connections = const [],
    this.blocked = const [],
  });
  final Member? profile;
  final List<FriendConnection> connections;
  final List<Member> blocked;
  factory FriendsSnapshot.fromJson(Map<String, dynamic> json) =>
      FriendsSnapshot(
        profile: json['profile'] == null
            ? null
            : Member.fromJson(json['profile'] as Map<String, dynamic>),
        connections: (json['connections'] as List)
            .map((e) => FriendConnection.fromJson(e as Map<String, dynamic>))
            .toList(),
        blocked: (json['blocked'] as List)
            .map((e) => Member.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

String? invitationCode(String input, String publicBaseUrl) {
  final value = input.trim();
  final valid = RegExp(r'^[a-f0-9]{48}$');
  if (valid.hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  String? code;
  if (uri.scheme == 'https' &&
      uri.origin == Uri.parse(publicBaseUrl).origin &&
      uri.path == '/invite') {
    code = uri.fragment;
  } else if (uri.scheme == 'ai.myrover.rover.friends' &&
      uri.host == 'friends' &&
      uri.path == '/invite') {
    code = uri.queryParameters['code'];
  }
  return code != null && valid.hasMatch(code) ? code : null;
}
