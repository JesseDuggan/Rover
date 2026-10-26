import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../accounts/account_library.dart';
import 'friend_models.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.library, this.invitation});
  final AccountLibrary? library;
  final String? invitation;
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final library = widget.library ?? AccountLibrary.instance;
  FriendsSnapshot? data;
  FriendConnection? found;
  final username = TextEditingController();
  final displayName = TextEditingController();
  final search = TextEditingController();
  final invitation = TextEditingController();
  String? error, inviteLink, inviteExpiry;
  bool busy = true;
  int operation = 0;
  late int generation;

  @override
  void initState() {
    super.initState();
    generation = library.sessionGeneration;
    invitation.text = widget.invitation ?? '';
    library.addListener(accountChanged);
    initialize();
  }

  @override
  void didUpdateWidget(covariant FriendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invitation != oldWidget.invitation) {
      invitation.text = widget.invitation ?? '';
    }
  }

  void accountChanged() {
    if (!mounted) return;
    if (generation != library.sessionGeneration || !library.signedIn) {
      generation = library.sessionGeneration;
      operation++;
      setState(() {
        data = null;
        found = null;
        inviteLink = null;
        inviteExpiry = null;
        error = null;
        busy = false;
        username.clear();
        displayName.clear();
        search.clear();
      });
    }
  }

  Future<void> initialize() async {
    try {
      await library.load();
      if (mounted) await reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not connect to Friends. Please refresh.';
          busy = false;
        });
      }
    }
  }

  Future<void> call(
    Future<dynamic> Function() action,
    void Function(dynamic) apply,
  ) async {
    final epoch = ++operation;
    final account = library.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await action();
      if (!mounted ||
          operation != epoch ||
          library.sessionGeneration != account ||
          !library.signedIn) {
        return;
      }
      setState(() => apply(result));
    } on LibraryException catch (e) {
      if (mounted && operation == epoch) setState(() => error = e.message);
    } catch (_) {
      if (mounted && operation == epoch) {
        setState(() => error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted && operation == epoch) setState(() => busy = false);
    }
  }

  void applyState(dynamic json) {
    data = FriendsSnapshot.fromJson(json as Map<String, dynamic>);
    username.text = data!.profile?.username ?? username.text;
    displayName.text = data!.profile?.displayName ?? displayName.text;
    found = null;
  }

  Future<void> reload() async {
    if (!library.signedIn) {
      setState(() => busy = false);
      return;
    }
    await call(() => library.request('GET', '/api/friends/state'), applyState);
  }

  Future<void> mutate(String method, String path, {Object? body}) =>
      call(() async {
        await library.request(method, path, body: body);
        return library.request('GET', '/api/friends/state');
      }, applyState);
  Future<void> signIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (await library.signIn() && mounted) await reload();
    } catch (_) {
      if (mounted) setState(() => error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> act(FriendConnection connection, String action) async {
    final account = library.sessionGeneration;
    if (action == 'remove' &&
        !await confirm(
          'Remove friend?',
          'Remove @${connection.member.username} from your friends?',
        )) {
      return;
    }
    if (!mounted || !library.signedIn || account != library.sessionGeneration) {
      return;
    }
    await mutate(
      'POST',
      '/api/friends/requests/${connection.requestId}/$action',
    );
  }

  Future<void> block(Member member, bool block) async {
    final account = library.sessionGeneration;
    if (!await confirm(
      block ? 'Block member?' : 'Unblock member?',
      block
          ? 'Remove your connection with @${member.username} and prevent further requests?'
          : 'Allow requests from @${member.username} again? Your previous friendship will not be restored.',
    )) {
      return;
    }
    if (mounted && library.signedIn && account == library.sessionGeneration) {
      await mutate(
        block ? 'PUT' : 'DELETE',
        '/api/friends/blocks/${member.id}',
      );
    }
  }

  Future<void> report(Member member) async {
    final account = library.sessionGeneration;
    var reason = 'harassment';
    final details = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Report @${member.username}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items:
                      const [
                            'harassment',
                            'hate',
                            'impersonation',
                            'spam',
                            'other',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => update(() => reason = v!),
                ),
                TextField(
                  controller: details,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'memberId': member.id,
                'reason': reason,
                'details': details.text,
              }),
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    // Dialog widgets finish their exit transition before this controller is disposed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    details.dispose();
    if (result == null ||
        !mounted ||
        !library.signedIn ||
        account != library.sessionGeneration) {
      return;
    }
    await call(
      () => library.request('POST', '/api/friends/reports', body: result),
      (_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report submitted')));
      },
    );
  }

  Future<void> resolve() async {
    setState(() => found = null);
    final code = invitationCode(invitation.text, library.publicBaseUrl);
    if (code == null) {
      setState(
        () => error = 'Enter a valid Walkabout invitation link or code.',
      );
      return;
    }
    await call(
      () => library.request(
        'POST',
        '/api/friends/invites/resolve',
        body: {'code': code},
      ),
      (json) => found = FriendConnection.fromJson(json as Map<String, dynamic>),
    );
  }

  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: username,
        readOnly: data?.profile != null,
        enabled: !busy,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        maxLength: 24,
        decoration: const InputDecoration(
          labelText: 'Username',
          prefixText: '@',
          helperText: '3-24 letters, numbers or underscores',
        ),
      ),
      TextField(
        controller: displayName,
        enabled: !busy,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
      FilledButton.icon(
        onPressed: busy
            ? null
            : () async {
                final account = library.sessionGeneration;
                if (!await confirm(
                  'Save member profile?',
                  'Your display name and username will be visible to signed-in members who look you up. Your username cannot be changed yet.',
                )) {
                  return;
                }
                if (!mounted ||
                    !library.signedIn ||
                    account != library.sessionGeneration) {
                  return;
                }
                await mutate(
                  'PUT',
                  '/api/friends/profile',
                  body: {
                    'username': username.text,
                    'displayName': displayName.text,
                  },
                );
              },
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save profile'),
      ),
    ],
  );
  Widget tile(FriendConnection connection) {
    final member = connection.member;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(member.displayName),
          subtitle: Text('@${member.username}'),
          trailing: PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Member options',
            onSelected: (action) {
              if (action == 'report') {
                report(member);
              } else if (action == 'block') {
                block(member, true);
              } else {
                act(connection, 'remove');
              }
            },
            itemBuilder: (_) => [
              if (connection.status == 'friend')
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove friend'),
                ),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'report', child: Text('Report')),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (connection.status == 'none')
              FilledButton.icon(
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add friend'),
                onPressed: busy
                    ? null
                    : () => mutate(
                        'POST',
                        '/api/friends/requests',
                        body: {'memberId': member.id},
                      ),
              ),
            if (connection.status == 'incoming') ...[
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
                onPressed: busy ? null : () => act(connection, 'accept'),
              ),
              TextButton(
                onPressed: busy ? null : () => act(connection, 'decline'),
                child: const Text('Decline'),
              ),
            ],
            if (connection.status == 'outgoing')
              TextButton(
                onPressed: busy ? null : () => act(connection, 'cancel'),
                child: const Text('Cancel request'),
              ),
          ],
        ),
        const Divider(),
      ],
    );
  }

  Widget list(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: widget.invitation == null ? 0 : 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            tooltip: 'Shared walks',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () => context.push('/shared-walks'),
          ),
          IconButton(
            tooltip: 'Refresh friends',
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : initialize,
          ),
        ],
        bottom: data?.profile == null
            ? null
            : const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Friends'),
                  Tab(text: 'Requests'),
                  Tab(text: 'Find'),
                  Tab(text: 'Blocked'),
                ],
              ),
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: !library.signedIn
                ? Center(
                    child: FilledButton(
                      onPressed: busy ? null : signIn,
                      child: const Text('Sign in or create account'),
                    ),
                  )
                : data == null
                ? Center(
                    child: TextButton(
                      onPressed: busy ? null : reload,
                      child: const Text('Retry'),
                    ),
                  )
                : data!.profile == null
                ? list([profile()])
                : TabBarView(
                    children: [
                      list([
                        ExpansionTile(
                          title: Text(data!.profile!.displayName),
                          subtitle: Text('@${data!.profile!.username}'),
                          children: [profile()],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.qr_code),
                              label: const Text('Create invitation'),
                              onPressed: busy
                                  ? null
                                  : () => call(
                                      () => library.request(
                                        'POST',
                                        '/api/friends/invites',
                                      ),
                                      (json) {
                                        inviteLink =
                                            '${library.publicBaseUrl}/invite#${json['code']}';
                                        inviteExpiry =
                                            json['expiresAtUtc'] as String;
                                      },
                                    ),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final account = library.sessionGeneration;
                                      if (!await confirm(
                                        'Revoke invitation?',
                                        'Existing invitation links will stop working.',
                                      )) {
                                        return;
                                      }
                                      if (!mounted ||
                                          !library.signedIn ||
                                          account !=
                                              library.sessionGeneration) {
                                        return;
                                      }
                                      await call(
                                        () => library.request(
                                          'DELETE',
                                          '/api/friends/invites',
                                        ),
                                        (_) {
                                          inviteLink = null;
                                          inviteExpiry = null;
                                        },
                                      );
                                    },
                              child: const Text('Revoke invitation'),
                            ),
                          ],
                        ),
                        if (inviteLink != null) ...[
                          Center(
                            child: QrImageView(
                              data: inviteLink!,
                              size: 220,
                              backgroundColor: Colors.white,
                              semanticsLabel:
                                  'Walkabout friend invitation QR code',
                            ),
                          ),
                          Text(
                            'Expires ${DateTime.parse(inviteExpiry!).toLocal().toString().split('.').first}',
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy invitation link'),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: inviteLink!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invitation copied'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (!data!.connections.any((c) => c.status == 'friend'))
                          const Text('No friends yet'),
                        for (final connection in data!.connections.where(
                          (c) => c.status == 'friend',
                        ))
                          tile(connection),
                      ]),
                      list([
                        const Text('Received'),
                        if (!data!.connections.any(
                          (c) => c.status == 'incoming',
                        ))
                          const ListTile(title: Text('No incoming requests')),
                        for (final c in data!.connections.where(
                          (c) => c.status == 'incoming',
                        ))
                          tile(c),
                        const Text('Sent'),
                        if (!data!.connections.any(
                          (c) => c.status == 'outgoing',
                        ))
                          const ListTile(title: Text('No sent requests')),
                        for (final c in data!.connections.where(
                          (c) => c.status == 'outgoing',
                        ))
                          tile(c),
                      ]),
                      list([
                        TextField(
                          controller: search,
                          enabled: !busy,
                          maxLength: 25,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Exact username',
                            prefixText: '@',
                            suffixIcon: IconButton(
                              tooltip: 'Find member',
                              icon: const Icon(Icons.search),
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() => found = null);
                                      call(
                                        () => library.request(
                                          'GET',
                                          '/api/friends/lookup?username=${Uri.encodeQueryComponent(search.text.trim())}',
                                        ),
                                        (json) =>
                                            found = FriendConnection.fromJson(
                                              json as Map<String, dynamic>,
                                            ),
                                      );
                                    },
                            ),
                          ),
                        ),
                        TextField(
                          controller: invitation,
                          enabled: !busy,
                          maxLength: 512,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Invitation link or code',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : resolve,
                          child: const Text('Review invitation'),
                        ),
                        if (found != null) tile(found!),
                      ]),
                      list([
                        if (data!.blocked.isEmpty)
                          const Text('No blocked members'),
                        for (final member in data!.blocked)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(member.displayName),
                            subtitle: Text('@${member.username}'),
                            trailing: TextButton(
                              onPressed: busy
                                  ? null
                                  : () => block(member, false),
                              child: const Text('Unblock'),
                            ),
                          ),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    operation++;
    library.removeListener(accountChanged);
    username.dispose();
    displayName.dispose();
    search.dispose();
    invitation.dispose();
    super.dispose();
  }
}
