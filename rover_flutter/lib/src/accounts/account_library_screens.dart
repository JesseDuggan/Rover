import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../api/walk_models.dart';
import '../api/adaptive_route_story_models.dart';
import '../memories/walk_replay_screen.dart';
import '../preferences/preferences_controller.dart';
import 'account_library.dart';
import '../memories/memory_store.dart';
import '../memories/memories_screen.dart';
import '../sharing/shared_walks.dart';
import '../sharing/story_share_data.dart';

class WalkaboutAccountScreen extends StatefulWidget {
  const WalkaboutAccountScreen({this.library, super.key});
  final AccountLibrary? library;
  @override
  State<WalkaboutAccountScreen> createState() => _WalkaboutAccountScreenState();
}

class _WalkaboutAccountScreenState extends State<WalkaboutAccountScreen> {
  late final AccountLibrary library = widget.library ?? AccountLibrary.instance;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _run(library.load);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        error = e is LibraryException
            ? e.message
            : 'Account service is unavailable. Please try again.';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
    final preferences = PreferencesScope.of(context);
    if (!await library.signIn()) return;
    await library.rememberGuest(preferences.preferences);
    final profiles = await library.list('profiles');
    final defaults = profiles.where((p) => p.isDefault);
    if (defaults.isNotEmpty) {
      await preferences.save(
        applyWalkingProfile(preferences.preferences, defaults.first.data),
      );
    }
  });
  Future<void> _signOut() => _run(() async {
    final preferences = PreferencesScope.of(context);
    final guest = await library.guestPreferences();
    if (guest != null) await preferences.save(guest);
    await library.signOut();
    await library.clearGuestBackup();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: busy ? null : () => _run(library.load),
            child: const Text('Retry'),
          ),
        ],
        if (!busy && !library.enabled && error == null)
          const Text(
            'Account sign-in is not enabled yet. Your guest walks are still available.',
          ),
        if (library.signedIn) ...[
          const Text(
            'Signed in',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Walking profiles'),
            onTap: busy
                ? null
                : () => context.push('/profile/walking-profiles'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Saved walks'),
            onTap: busy ? null : () => context.push('/profile/saved-walks'),
          ),
          OutlinedButton(
            onPressed: busy ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ] else ...[
          FilledButton(
            onPressed: busy || !library.enabled ? null : _signIn,
            child: const Text('Create my account'),
          ),
          OutlinedButton(
            onPressed: busy || !library.enabled ? null : _signIn,
            child: const Text('Sign in'),
          ),
          TextButton(
            onPressed: busy || !library.enabled ? null : _signIn,
            child: const Text('Forgot password?'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    await PreferencesScope.of(context).continueAsGuest();
                    if (context.mounted) context.go('/home');
                  },
            child: const Text('Continue as guest'),
          ),
        ],
      ],
    ),
  );
}

class PersonalLibraryScreen extends StatefulWidget {
  const PersonalLibraryScreen({required this.kind, this.library, super.key});
  final String kind;
  final AccountLibrary? library;
  @override
  State<PersonalLibraryScreen> createState() => _PersonalLibraryScreenState();
}

class _PersonalLibraryScreenState extends State<PersonalLibraryScreen> {
  late final AccountLibrary library = widget.library ?? AccountLibrary.instance;
  List<LibraryItem> items = [];
  bool busy = true;
  String? error;
  bool get profiles => widget.kind == 'profiles';
  int get limit => profiles ? library.profileLimit : library.walkLimit;
  @override
  void initState() {
    super.initState();
    library.addListener(_accountChanged);
    _run(() async {
      await library.load();
      await _reload();
    });
  }

  void _accountChanged() {
    if (!library.signedIn && mounted) setState(() => items = []);
  }

  @override
  void dispose() {
    library.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = library.sessionGeneration;
    final result = library.signedIn
        ? await library.list(widget.kind)
        : <LibraryItem>[];
    items = library.signedIn && generation == library.sessionGeneration
        ? result
        : [];
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        error = e is LibraryException
            ? e.message
            : 'Unable to update your library. Please try again.';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _name(String initial) async {
    var name = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(profiles ? 'Profile name' : 'Walk name'),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 80,
          onChanged: (value) => name = value,
          decoration: const InputDecoration(labelText: 'Name'),
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialog, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(dialog, name.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _signInToSave() async {
    final preferences = PreferencesScope.of(context).preferences;
    var ready = false;
    await _run(() async {
      if (!await library.signIn()) return;
      await library.rememberGuest(preferences);
      await _reload();
      ready = true;
    });
    if (ready && mounted) await _add();
  }

  Future<void> _add() async {
    final walkId = profiles
        ? null
        : ActiveRoamScope.of(context).session.apiWalkSessionId;
    if (items.length >= limit || (!profiles && walkId == null)) {
      setState(
        () => error = items.length >= limit
            ? 'Library full. Delete an item to make room.'
            : 'Create a walk before saving it.',
      );
      return;
    }
    final name = await _name('');
    if (name == null || !mounted) return;
    final preferences = PreferencesScope.of(context).preferences;
    await _run(() async {
      Map<String, dynamic> data;
      if (profiles) {
        data = walkingProfileData(preferences);
      } else {
        if (walkId == null) {
          throw const LibraryException('Create a walk before saving it.');
        }
        final walk = await library.request(
          'GET',
          '/api/walks/$walkId',
          authenticated: false,
        );
        // Capture only the already-generated pack; saving never starts paid research.
        dynamic stories;
        try {
          stories = await library.request(
            'GET',
            '/api/walks/$walkId/route-story-pack',
            authenticated: false,
          );
        } on LibraryException {
          stories = null;
        }
        data = {'walk': walk, 'stories': stories};
      }
      await library.save(
        widget.kind,
        newLibraryId(),
        name,
        data,
        isDefault: profiles && items.isEmpty,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$name saved')));
      }
    });
  }

  Future<void> _action(LibraryItem item, String action) async {
    if (action == 'rename') {
      final name = await _name(item.name);
      if (name == null || !mounted) return;
      await _run(() async {
        await library.save(
          widget.kind,
          item.id,
          name,
          item.data,
          revision: item.revision,
          isDefault: item.isDefault,
        );
        await _reload();
      });
    } else if (action == 'delete') {
      if (!await _confirm(
            'Delete ${item.name}?',
            'This removes the saved item from your account. Your current walk is unchanged.',
          ) ||
          !mounted) {
        return;
      }
      await _run(() async {
        await library.delete(widget.kind, item);
        await _reload();
      });
    } else if (action == 'replace') {
      if (!await _confirm(
            'Update ${item.name}?',
            'Replace this profile with your current walking preferences?',
          ) ||
          !mounted) {
        return;
      }
      final data = walkingProfileData(PreferencesScope.of(context).preferences);
      await _run(() async {
        await library.save(
          'profiles',
          item.id,
          item.name,
          data,
          revision: item.revision,
          isDefault: item.isDefault,
        );
        await _reload();
      });
    } else if (action == 'default') {
      await _run(() async {
        await library.save(
          'profiles',
          item.id,
          item.name,
          item.data,
          revision: item.revision,
          isDefault: true,
        );
        await _reload();
      });
    } else if (action == 'apply') {
      final preferences = PreferencesScope.of(context);
      await _run(() async {
        await library.rememberGuest(preferences.preferences);
        await preferences.save(
          applyWalkingProfile(preferences.preferences, item.data),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${item.name} applied to future walks')),
          );
        }
      });
    } else if (action == 'preview') {
      final active = ActiveRoamScope.of(context);
      if (active.session.status == RoamSessionStatus.active ||
          active.session.status == RoamSessionStatus.paused) {
        setState(
          () => error = 'Finish your current walk before opening a saved walk.',
        );
        return;
      }
      await _run(() async {
        final json = await library.request(
          'POST',
          '/api/account-library/walks/${item.id}/preview',
        );
        final restored = WalkSession.fromJson(json as Map<String, dynamic>);
        final original = item.data['walk'] as Map<String, dynamic>;
        await MemoryStore().linkSession(
          restored.walkSessionId,
          original['walkSessionId'] as String,
        );
        await active.previewSavedWalk(restored);
        if (mounted) context.push('/home/route-preview');
      });
    } else if (action == 'details') {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SavedWalkDetails(item: item, library: library),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(profiles ? 'Walking profiles' : 'Saved walks'),
      actions: [
        IconButton(
          tooltip: 'Refresh library',
          onPressed: busy
              ? null
              : () => _run(() async {
                  await library.load();
                  await _reload();
                }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!busy && !library.signedIn)
          FilledButton(
            onPressed: library.enabled ? _signInToSave : null,
            child: Text(
              profiles ? 'Sign in to save preferences' : 'Sign in to save walk',
            ),
          ),
        if (!busy && !library.enabled && error == null)
          const Text('Account saving is not enabled on the server yet.'),
        if (library.signedIn) ...[
          Text(
            '${items.length} of $limit saved',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy || items.length >= limit ? null : _add,
            icon: const Icon(Icons.add),
            label: Text(
              profiles ? 'Save current preferences' : 'Save current walk',
            ),
          ),
          if (items.length >= limit)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Library full. Delete an item to make room.'),
            ),
          for (final item in items)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: Icon(profiles ? Icons.tune : Icons.bookmark_outline),
              title: Text(item.name),
              subtitle: Text(
                profiles
                    ? (item.isDefault
                          ? 'Default profile'
                          : 'Walking preferences')
                    : 'Saved route and stops',
              ),
              onTap: busy
                  ? null
                  : () => _action(item, profiles ? 'apply' : 'details'),
              trailing: PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'Manage ${item.name}',
                onSelected: (value) => _action(item, value),
                itemBuilder: (_) => [
                  if (profiles) ...[
                    const PopupMenuItem(
                      value: 'apply',
                      child: Text('Use profile'),
                    ),
                    const PopupMenuItem(
                      value: 'replace',
                      child: Text('Update from current preferences'),
                    ),
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Make default'),
                    ),
                  ] else
                    const PopupMenuItem(
                      value: 'preview',
                      child: Text('Open route preview'),
                    ),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

class SavedWalkDetails extends StatelessWidget {
  SavedWalkDetails({required this.item, required this.library, super.key})
    : _sessionGeneration = library.sessionGeneration;
  final LibraryItem item;
  final AccountLibrary library;
  final int _sessionGeneration;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) =>
        library.signedIn && library.sessionGeneration == _sessionGeneration
        ? _details(context)
        : const Scaffold(
            body: Center(child: Text('Sign in to view saved walks.')),
          ),
  );
  Widget _details(BuildContext context) {
    final walk = item.data['walk'] as Map<String, dynamic>;
    final stops = (walk['stops'] as List<dynamic>?) ?? [];
    final pack = item.data['stories'];
    final stories = pack is Map<String, dynamic>
        ? (pack['stories'] as List<dynamic>? ?? [])
        : [];
    final replayStories = stories
        .whereType<Map<String, dynamic>>()
        .map(AdaptiveRouteStory.fromJson)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            tooltip: 'Share walk',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShareWalkScreen(
                  library: library,
                  stories: replayStories.map(storyShareData).toList(),
                  journey: MemoryJourney(
                    id: walk['walkSessionId'] as String,
                    route: WalkSession.fromJson(walk).toRoam(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(walk['routeSummary'] as String? ?? ''),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Replay walk'),
            subtitle: const Text('Private on this device'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WalkReplayScreen(
                  journey: MemoryJourney(
                    id: walk['walkSessionId'] as String,
                    route: WalkSession.fromJson(walk).toRoam(),
                  ),
                  stories: replayStories,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Route memories'),
            subtitle: const Text('Private on this device'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MemoriesScreen(
                  captureEnabled: false,
                  stories: replayStories,
                  journey: MemoryJourney(
                    id: walk['walkSessionId'] as String,
                    route: WalkSession.fromJson(walk).toRoam(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final stop in stops)
            ListTile(
              title: Text(stop['name'] as String? ?? ''),
              subtitle: Text(stop['shortDescription'] as String? ?? ''),
            ),
          const Divider(),
          Text('Saved stories', style: Theme.of(context).textTheme.titleLarge),
          if (stories.isEmpty)
            const Text('No story text was available when this walk was saved.'),
          for (final story in stories)
            ExpansionTile(
              title: Text(story['title'] as String? ?? 'Story'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_storyText(story)),
                ),
                for (final source in (story['sources'] as List<dynamic>? ?? []))
                  ListTile(
                    title: Text(
                      (source['title'] ?? source['providerName'] ?? 'Source')
                          .toString(),
                    ),
                    subtitle: SelectableText(
                      (source['attribution'] ?? source['url'] ?? '').toString(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _storyText(dynamic story) {
    final variants = story['variants'] as List<dynamic>? ?? [];
    if (variants.isEmpty) {
      return 'Narration was not available when this walk was saved.';
    }
    final standard = variants.where((v) => v['length'] == 'Standard');
    return ((standard.isEmpty ? variants.first : standard.first)['narration'] ??
            '')
        .toString();
  }
}
