import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../accounts/account_library.dart';
import '../adventure/roam.dart';
import '../friends/friend_models.dart';
import '../location/rover_location.dart';
import '../maps/rover_map_view.dart';
import '../memories/memory_store.dart';
import '../memories/memory_thumbnail.dart';
import 'shared_video_player.dart';
import '../voice/rover_audio_services.dart';
import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import 'story_share_data.dart';
import '../memories/walk_trail_store.dart';
import '../memories/walk_replay.dart';
import 'shared_replay_screen.dart';
import 'retry_share_screen.dart';

String _id() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
Map<String, double> _point(RoverLatLng p) => {
  'latitude': p.latitude,
  'longitude': p.longitude,
};
RoverLatLng _location(dynamic p) => RoverLatLng(
  latitude: (p['latitude'] as num).toDouble(),
  longitude: (p['longitude'] as num).toDouble(),
);

Map<String, dynamic> sharedDraft(
  MemoryJourney? journey,
  String title,
  List<WalkMemory> selected,
  List<String> recipients,
  bool locations,
) => {
  'title': title.trim(),
  'includeLocations': locations,
  'recipients': recipients,
  // Bound the preview payload without transmitting the original session or POI addresses.
  'route': locations && journey != null
      ? [
          for (
            var i = 0;
            i < journey.route.routeGeometry.length;
            i += max(1, (journey.route.routeGeometry.length / 3999).ceil())
          )
            _point(journey.route.routeGeometry[i]),
        ]
      : [],
  'media': [
    for (final m in selected.where((m) => !m.details.sharingLocked))
      {
        'id': _id(),
        'kind': m.isVideo ? 'video' : 'photo',
        'caption': m.details.caption,
        'location': locations && m.details.location != null
            ? _point(m.details.location!)
            : null,
      },
  ],
};

class ShareWalkScreen extends StatefulWidget {
  const ShareWalkScreen({
    super.key,
    this.journey,
    this.initialMemoryIds = const {},
    this.stories = const [],
    this.library,
    this.store,
    this.trailStore,
  });
  final MemoryJourney? journey;
  final Set<String> initialMemoryIds;
  final List<Map<String, dynamic>> stories;
  final AccountLibrary? library;
  final MemoryStore? store;
  final WalkTrailStore? trailStore;
  @override
  State<ShareWalkScreen> createState() => _ShareWalkScreenState();
}

class _ShareWalkScreenState extends State<ShareWalkScreen> {
  late final library = widget.library ?? AccountLibrary.instance;
  late final store = widget.store ?? MemoryStore();
  late final title = TextEditingController(
    text: widget.stories.isNotEmpty
        ? widget.stories.first['title'] as String
        : widget.journey?.displayName ?? 'Memories',
  );
  List<Map<String, dynamic>> stories = [];
  List<Map<String, dynamic>> trail = [];
  bool includeReplay = false;
  final selectedStories = <int>{};
  List<Map<String, dynamic>> get includedStories => [
    for (final index in selectedStories) stories[index],
  ];
  List<Member> friends = [];
  List<WalkMemory> memories = [];
  final recipients = <String>{}, selected = <String>{};
  bool busy = true, locations = false, member = false;
  String audience = 'selectedFriends';
  String? error, progress;
  String? pendingShareId;
  late int generation;
  @override
  void initState() {
    super.initState();
    generation = library.sessionGeneration;
    selected.addAll(widget.initialMemoryIds);
    stories = widget.stories;
    selectedStories.addAll(List.generate(min(10, stories.length), (i) => i));
    library.addListener(changed);
    load();
  }

  void changed() {
    if (!mounted) return;
    if (generation != library.sessionGeneration || !library.signedIn) {
      generation = library.sessionGeneration;
      setState(() {
        friends = [];
        memories = [];
        recipients.clear();
        audience = 'selectedFriends';
        selected.clear();
        stories = [];
        trail = [];
        includeReplay = false;
        selectedStories.clear();
        member = false;
        error = null;
        pendingShareId = null;
      });
    }
  }

  bool valid(int g) =>
      mounted && library.signedIn && library.sessionGeneration == g;
  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await library.load();
      if (!mounted || !library.signedIn) return;
      final g = library.sessionGeneration;
      final state = FriendsSnapshot.fromJson(
        await library.request('GET', '/api/friends/state')
            as Map<String, dynamic>,
      );
      final id = widget.journey == null
          ? null
          : await store.journeyId(widget.journey!.id);
      final all = await store.list();
      final recorded = id == null
          ? <ReplaySegment>[]
          : replaySegments(
              await (widget.trailStore ?? WalkTrailStore(memoryStore: store))
                  .readJourney(id),
            );
      final rows = <Map<String, dynamic>>[
        for (var section = 0; section < recorded.length; section++)
          for (final fix in recorded[section].fixes)
            {
              'at': fix.at.toUtc().toIso8601String(),
              'latitude': fix.location.latitude,
              'longitude': fix.location.longitude,
              'segment': section,
            },
      ];
      var foundStories = widget.stories;
      if (foundStories.isEmpty && id != null) {
        final walks = await library.list('walks');
        for (final item in walks) {
          final walk = item.data['walk'];
          if (walk is Map &&
              walk['walkSessionId'] is String &&
              await store.journeyId(walk['walkSessionId'] as String) == id) {
            foundStories = storyPackShareData(item.data['stories']);
            if (foundStories.isNotEmpty) break;
          }
        }
        if (foundStories.isEmpty) {
          try {
            foundStories = storyPackShareData(
              await library.request(
                'GET',
                '/api/walks/${Uri.encodeComponent(id)}/route-story-pack',
              ),
            );
          } on LibraryException {
            // Old sessions can expire; never generate unrelated replacement stories.
          }
        }
      }
      if (!valid(g)) return;
      setState(() {
        stories = foundStories;
        trail = rows;
        selectedStories
          ..clear()
          ..addAll(List.generate(min(10, stories.length), (i) => i));
        member = state.profile != null;
        friends = state.connections
            .where((c) => c.status == 'friend')
            .map((c) => c.member)
            .toList();
        memories = id == null
            ? all
            : all.where((m) => m.details.journey?.id == id).toList();
        selected.removeWhere((id) => !memories.any((m) => m.id == id));
        selected.removeWhere(
          (id) => memories.any((m) => m.id == id && m.details.sharingLocked),
        );
        recipients.removeWhere((r) => !friends.any((f) => f.id == r));
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not load sharing. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signIn() async {
    try {
      if (await library.signIn()) await load();
    } catch (_) {
      if (mounted) setState(() => error = 'Sign-in failed. Please retry.');
    }
  }

  Future<void> share() async {
    if (widget.journey == null && selected.isEmpty && includedStories.isEmpty) {
      return;
    }
    final g = library.sessionGeneration;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          widget.journey == null ? 'Share these memories?' : 'Share this walk?',
        ),
        content: Text(
          '${includedStories.length} stories (text and sources) will be shared. '
          '${includeReplay ? 'Your actual GPS path, recording times and memory capture times will also be uploaded for replay. ' : 'Your actual GPS recording will remain on this device. '}'
          '${selected.length} selected memories will be uploaded for ${audience == 'allFriends' ? 'all accepted friends, including friends you add later' : '${recipients.length} selected friends'}. ${locations ? 'The route and capture locations will be visible.' : 'The route and capture locations will be hidden.'}\n\nFriends may save or screenshot what they see. Removing access cannot erase their copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (yes != true || !valid(g)) return;
    setState(() {
      busy = true;
      error = null;
      progress = 'Creating private draft';
    });
    String? id;
    bool recoverable = false;
    void check() {
      if (!valid(g)) {
        throw const LibraryException('Account changed. Sharing stopped.');
      }
    }

    try {
      final fresh = await store.list();
      check();
      final files = fresh
          .where((m) => selected.contains(m.id) && !m.details.sharingLocked)
          .toList();
      if (files.length != selected.length) {
        throw const LibraryException(
          'A selected memory was removed or marked private. Refresh and choose again.',
        );
      }
      final draft = sharedDraft(
        widget.journey,
        title.text,
        files,
        audience == 'allFriends' ? [] : recipients.toList(),
        locations,
      );
      draft['audience'] = audience;
      draft['includeReplay'] = includeReplay && locations;
      draft['trail'] = includeReplay && locations ? trail : [];
      if (includeReplay && locations) {
        for (var i = 0; i < files.length; i++) {
          draft['media'][i]['capturedAt'] = files[i].details.capturedAt
              ?.toUtc()
              .toIso8601String();
        }
      }
      draft['stories'] = [
        for (final story in includedStories)
          {
            ...story,
            'id': _id(),
            'location': locations ? story['location'] : null,
          },
      ];
      final created = await library.request(
        'POST',
        '/api/shared-walks',
        body: draft,
      );
      check();
      id = created['id'] as String;
      if (includeReplay) {
        final saved =
            await library.request('GET', '/api/shared-walks/$id') as Map;
        check();
        if ((saved['trail'] as List?)?.length != trail.length) {
          throw const LibraryException(
            'Replay sharing requires the updated server. Nothing was published.',
          );
        }
      }
      if (audience == 'allFriends') {
        final saved =
            await library.request('GET', '/api/shared-walks/$id') as Map;
        check();
        if (saved['audience'] != 'allFriends') {
          throw const LibraryException(
            'All-friends sharing requires the updated server.',
          );
        }
      }
      if (includedStories.isNotEmpty) {
        final saved =
            await library.request('GET', '/api/shared-walks/$id') as Map;
        check();
        if ((saved['stories'] as List?)?.length != includedStories.length) {
          throw const LibraryException(
            'Story sharing requires the updated server.',
          );
        }
      }
      await store.saveUploadFiles(id, {
        for (var i = 0; i < files.length; i++)
          draft['media'][i]['id'] as String: files[i].id,
      });
      check();
      recoverable = true;
      for (var i = 0; i < files.length; i++) {
        check();
        setState(
          () => progress = 'Uploading memory ${i + 1} of ${files.length}',
        );
        await library.transferSharedMedia(
          'PUT',
          '/api/shared-walks/$id/media/${draft['media'][i]['id']}',
          upload: files[i].file,
        );
        check();
      }
      setState(() => progress = 'Publishing to friends');
      await library.request('POST', '/api/shared-walks/$id/publish');
      check();
      try { await store.forgetUpload(id); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.journey == null ? 'Memories shared' : 'Walk shared',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (id != null && valid(g) && !recoverable) {
        try {
          await library.request('DELETE', '/api/shared-walks/$id');
        } catch (_) {}
      }
      if (valid(g)) {
        if (recoverable) pendingShareId = id;
        setState(
          () => error = e is LibraryException ? e.message : 'Sharing did not finish. Check Sent for unfinished drafts, then retry.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error!),
            action: pendingShareId == null ? null : SnackBarAction(label: 'Retry', onPressed: retryPending),
          ));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> retryPending() async {
    final id = pendingShareId;
    if (id == null || busy) return;
    final finished = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => RetryShareScreen(id: id, library: library, store: store),
    ));
    if (finished == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: progress == null,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.journey == null && widget.stories.isNotEmpty
              ? 'Share story'
              : widget.journey == null
              ? 'Share memories'
              : 'Share walk',
        ),
      ),
      body: !library.signedIn && !busy
          ? Center(
              child: FilledButton(
                onPressed: signIn,
                child: const Text('Sign in'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(progress!),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!busy && error != null)
                  TextButton(onPressed: load, child: const Text('Retry')),
                TextField(
                  controller: title,
                  maxLength: 160,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: audience,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Share with'),
                  items: const [
                    DropdownMenuItem(
                      value: 'selectedFriends',
                      child: Text('Selected friends'),
                    ),
                    DropdownMenuItem(
                      value: 'allFriends',
                      child: Text('All friends'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => audience = value!),
                ),
                if (!busy)
                  Text(
                    'Stories (${selectedStories.length}/10)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                if (!busy && stories.isEmpty)
                  const Text('No saved stories found for this walk.'),
                for (var i = 0; i < stories.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selectedStories.contains(i),
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            if (value == true && selectedStories.length < 10) {
                              selectedStories.add(i);
                            } else {
                              selectedStories.remove(i);
                            }
                          }),
                    title: Text(stories[i]['title'] as String),
                    subtitle: Text(
                      stories[i]['notice'] as String? ??
                          'Story text and sources',
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.journey == null
                        ? 'Include capture locations'
                        : 'Include route and capture locations',
                  ),
                  value: locations,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          locations = v;
                          if (!v) includeReplay = false;
                        }),
                ),
                if (widget.journey != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include my actual walked path'),
                    subtitle: Text(
                      trail.isEmpty
                          ? 'No GPS recording on this device'
                          : trail.length > 4000
                          ? 'Recording too large to share; local replay is still available'
                          : 'Shares GPS locations and times so friends can replay this walk',
                    ),
                    value: includeReplay,
                    onChanged: busy || trail.isEmpty || trail.length > 4000
                        ? null
                        : (value) => setState(() {
                            includeReplay = value;
                            if (value) locations = true;
                          }),
                  ),
                if (includeReplay)
                  for (final section in replaySegments(trail))
                    SizedBox(
                      height: 180,
                      child: RoverMapView(
                        currentLocation: null,
                        overview: true,
                        height: 180,
                        enableExpand: false,
                        routeGeometry: section.fixes
                            .map((p) => p.location)
                            .toList(),
                        orderedStops: const [],
                      ),
                    ),
                if (locations &&
                    widget.journey != null &&
                    widget.journey!.route.routeGeometry.isNotEmpty)
                  SizedBox(
                    height: 220,
                    child: RoverMapView(
                      currentLocation: null,
                      overview: true,
                      height: 220,
                      enableExpand: false,
                      routeGeometry: widget.journey!.route.routeGeometry,
                      orderedStops: const [],
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Friends', style: Theme.of(context).textTheme.titleMedium),
                if (!busy && (!member || friends.isEmpty))
                  TextButton.icon(
                    onPressed: () async {
                      await context.push('/friends');
                      if (mounted) await load();
                    },
                    icon: const Icon(Icons.people_outline),
                    label: Text(
                      member ? 'Add friends' : 'Create member profile',
                    ),
                  ),
                for (final f
                    in audience == 'selectedFriends' ? friends : <Member>[])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.displayName),
                    subtitle: Text('@${f.username}'),
                    value: recipients.contains(f.id),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            if (v == true && recipients.length < 20) {
                              recipients.add(f.id);
                            } else {
                              recipients.remove(f.id);
                            }
                          }),
                  ),
                const Divider(),
                Text(
                  'Memories (${selected.length}/10)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (memories.isEmpty && !busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No memories for this walk'),
                  ),
                for (final m in memories)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: SizedBox(
                      width: 56,
                      height: 56,
                      child: MemoryThumbnail(memory: m),
                    ),
                    title: Text(
                      m.details.caption.isEmpty
                          ? (m.isVideo ? 'Video' : 'Photo')
                          : m.details.caption,
                    ),
                    subtitle: Text(
                      m.details.sharingLocked
                          ? 'Private - excluded from sharing'
                          : m.details.capturedAt
                                    ?.toLocal()
                                    .toString()
                                    .split('.')
                                    .first ??
                                '',
                    ),
                    value: selected.contains(m.id),
                    onChanged: busy || m.details.sharingLocked
                        ? null
                        : (v) => setState(() {
                            if (v == true && selected.length < 10) {
                              selected.add(m.id);
                            } else {
                              selected.remove(m.id);
                            }
                          }),
                  ),
                const SizedBox(height: 20),
                if (pendingShareId != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Retry unfinished upload'),
                    onPressed: busy ? null : retryPending,
                  ),
                FilledButton.icon(
                  onPressed:
                      busy ||
                          pendingShareId != null ||
                          !member ||
                          (audience == 'selectedFriends' &&
                              recipients.isEmpty) ||
                          (widget.journey == null &&
                              selected.isEmpty &&
                              includedStories.isEmpty)
                      ? null
                      : share,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    audience == 'allFriends'
                        ? 'Share with all friends'
                        : 'Share with selected friends',
                  ),
                ),
              ],
            ),
    ),
  );
  @override
  void dispose() {
    library.removeListener(changed);
    title.dispose();
    super.dispose();
  }
}

class SharedWalksScreen extends StatefulWidget {
  const SharedWalksScreen({super.key, this.library});
  final AccountLibrary? library;
  @override
  State<SharedWalksScreen> createState() => _SharedWalksScreenState();
}

class _SharedWalksScreenState extends State<SharedWalksScreen> {
  late final library = widget.library ?? AccountLibrary.instance;
  List<Map<String, dynamic>> items = [];
  bool busy = true;
  String? error;
  late int generation;
  @override
  void initState() {
    super.initState();
    generation = library.sessionGeneration;
    library.addListener(changed);
    load();
  }

  void changed() {
    if (mounted &&
        (generation != library.sessionGeneration || !library.signedIn)) {
      generation = library.sessionGeneration;
      setState(() => items = []);
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await library.load();
      final g = library.sessionGeneration;
      if (!library.signedIn) return;
      final result = await library.request('GET', '/api/shared-walks') as List;
      if (mounted && library.signedIn && g == library.sessionGeneration) {
        setState(() => items = result.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not load shared walks.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SharedWalkScreen(id: item['id'] as String, library: library),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Shared walks'),
        actions: [
          IconButton(
            tooltip: 'Refresh shared walks',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Shared with me'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          if (!library.signedIn && !busy)
            TextButton(
              onPressed: () async {
                try {
                  if (await library.signIn()) await load();
                } catch (_) {
                  if (mounted) setState(() => error = 'Sign-in failed.');
                }
              },
              child: const Text('Sign in'),
            ),
          Expanded(
            child: TabBarView(
              children: [
                for (final owned in [false, true])
                  ListView(
                    children: [
                      if (!busy && !items.any((i) => i['owned'] == owned))
                        const ListTile(title: Text('No shared walks yet')),
                      for (final item in items.where(
                        (i) => i['owned'] == owned,
                      ))
                        ListTile(
                          leading: Icon(
                            item['status'] == 'draft'
                                ? Icons.cloud_upload_outlined
                                : Icons.route_outlined,
                          ),
                          title: Text(item['title'] as String),
                          subtitle: Text(
                            '${item['sender']} - ${item['status'] == 'private'
                                ? 'Private'
                                : item['status'] == 'draft'
                                ? 'Unfinished draft'
                                : '${(item['media'] as List).length} memories'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(item),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    library.removeListener(changed);
    super.dispose();
  }
}

class SharedWalkScreen extends StatefulWidget {
  const SharedWalkScreen({super.key, required this.id, required this.library});
  final String id;
  final AccountLibrary library;
  @override
  State<SharedWalkScreen> createState() => _SharedWalkScreenState();
}

class _SharedWalkScreenState extends State<SharedWalkScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? walk;
  String? error;
  bool busy = true;
  late final int generation = widget.library.sessionGeneration;
  Timer? timer;
  final RoverTextToSpeech speech = DeviceTextToSpeech();
  String? playingStory;
  int playback = 0;
  bool foreground = true;

  Future<void> stopStory() async {
    playback++;
    if (playingStory == null) return;
    if (mounted) setState(() => playingStory = null);
    try {
      await speech.stop();
    } catch (_) {}
  }

  Future<void> playStory(String id) async {
    final active = context
        .getInheritedWidgetOfExactType<ActiveRoamScope>()
        ?.notifier;
    if (active?.session.status == RoamSessionStatus.active) {
      setState(
        () => error = 'Pause your walk before listening to a shared story.',
      );
      return;
    }
    if (playingStory == id) {
      await stopStory();
      return;
    }
    await stopStory();
    final requested = playback;
    await load(quiet: true);
    if (!valid || !foreground || requested != playback || walk == null) return;
    final stories = (walk!['stories'] as List?) ?? [];
    final matches = stories.where((s) => s['id'] == id);
    if (matches.isEmpty) return;
    final story = matches.first as Map;
    final token = ++playback;
    setState(() => playingStory = id);
    try {
      await speech.configure(rate: 0.48);
      var remaining = [
        story['notice'],
        story['narration'],
      ].whereType<String>().where((s) => s.isNotEmpty).join('\n');
      // Keep each utterance below the platform TTS input limit.
      while (remaining.isNotEmpty && valid && token == playback) {
        var end = min(3000, remaining.length);
        if (end < remaining.length) {
          final space = remaining.lastIndexOf(' ', end);
          if (space > 0) end = space;
        }
        await speech.speak(remaining.substring(0, end));
        remaining = remaining.substring(end).trimLeft();
      }
    } catch (_) {
      if (valid && token == playback) {
        setState(
          () => error =
              'Could not play narration. Story text is available below.',
        );
      }
    } finally {
      if (mounted && token == playback) setState(() => playingStory = null);
    }
  }

  bool get valid =>
      mounted &&
      widget.library.signedIn &&
      generation == widget.library.sessionGeneration;
  @override
  void initState() {
    super.initState();
    widget.library.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => load(quiet: true),
    );
  }

  void changed() {
    if (!valid && mounted) {
      unawaited(stopStory());
      setState(() {
        walk = null;
        error = 'Sign in again to view this shared walk.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      load();
    } else {
      unawaited(stopStory());
    }
  }

  Future<void> load({bool quiet = false}) async {
    if (!valid || (quiet && busy)) return;
    if (!quiet) setState(() => busy = true);
    try {
      final data = await widget.library.request(
        'GET',
        '/api/shared-walks/${widget.id}',
      );
      if (valid) {
        setState(() {
          walk = data as Map<String, dynamic>;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          walk = null;
          error = e is LibraryException
              ? e.message
              : 'Shared walk unavailable.';
        });
        unawaited(stopStory());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove sharing access?'),
        content: const Text(
          'This removes the shared copy for every recipient. Your original walk and memories remain on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !valid) return;
    setState(() => busy = true);
    try {
      await widget.library.request('DELETE', '/api/shared-walks/${widget.id}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not remove sharing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> makePrivate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Make this walk private?'),
        content: const Text(
          'Friends will lose access to this shared walk, its stories and memories. Your copy is kept. Previously saved copies and screenshots cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Make private'),
          ),
        ],
      ),
    );
    if (yes != true || !valid) return;
    setState(() => busy = true);
    try {
      await widget.library.request(
        'POST',
        '/api/shared-walks/${widget.id}/private',
      );
      await stopStory();
      if (valid) await load();
    } catch (e) {
      if (valid) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not change privacy. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void media(dynamic m) {
    unawaited(stopStory());
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SharedMediaScreen(
          shareId: widget.id,
          media: m as Map<String, dynamic>,
          library: widget.library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memories = (walk?['media'] as List?) ?? [];
    final located = memories.where((m) => m['location'] != null).toList();
    final route = (walk?['route'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(walk?['title'] as String? ?? 'Shared walk'),
        actions: [
          if (walk?['owned'] == true && walk?['status'] == 'published')
            IconButton(
              tooltip: 'Make private',
              onPressed: busy ? null : makePrivate,
              icon: const Icon(Icons.lock_outline),
            ),
          if (walk?['owned'] == true)
            IconButton(
              tooltip: 'Remove shared walk',
              onPressed: busy ? null : remove,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(error!)),
          if (walk != null) ...[
            if (walk!['owned'] == true && walk!['status'] == 'draft')
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Retry upload'),
                  onPressed: busy ? null : () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => RetryShareScreen(id: widget.id, library: widget.library),
                    ));
                    if (valid) await load();
                  },
                ),
              ),
            if (walk!['owned'] == true)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(walk!['status'] == 'draft' ? 'Delete unfinished upload' : 'Delete shared walk'),
                subtitle: const Text('Your original walk and memories stay on this phone.'),
                onTap: busy ? null : remove,
              ),
            if ((walk!['trail'] as List?)?.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Replay walked path'),
                onTap: () async {
                  await stopStory();
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SharedReplayScreen(
                        shareId: widget.id,
                        library: widget.library,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              title: Text('From ${walk!['sender']}'),
              subtitle: Text(
                walk!['status'] == 'draft'
                    ? 'Unfinished draft - not visible to friends'
                    : walk!['status'] == 'private'
                    ? 'Private - only you'
                    : '${walk!['audience'] == 'allFriends' ? 'Shared with all friends, including future friends' : 'Shared with selected friends'}${route.isEmpty ? ' - locations hidden' : ''}',
              ),
            ),
            if (route.isNotEmpty || located.isNotEmpty)
              SizedBox(
                height: 280,
                child: RoverMapView(
                  currentLocation: null,
                  overview: true,
                  height: 280,
                  enableExpand: false,
                  routeGeometry: route.map(_location).toList(),
                  orderedStops: [
                    for (var i = 0; i < located.length; i++)
                      OrderedRoverStop(
                        sequence: i + 1,
                        stop: RoverStop(
                          id: located[i]['id'] as String,
                          name: 'Memory ${i + 1}',
                          image: '',
                          shortDescription: '',
                          estimatedVisitMinutes: 0,
                          coordinates: _location(located[i]['location']),
                          category: 'Memory',
                          whySelected: '',
                        ),
                      ),
                  ],
                  onStopTap: (stop) =>
                      media(located.firstWhere((m) => m['id'] == stop.stop.id)),
                ),
              ),
            for (final story in (walk!['stories'] as List?) ?? [])
              ExpansionTile(
                leading: IconButton(
                  tooltip: playingStory == story['id']
                      ? 'Stop story'
                      : 'Read story aloud',
                  icon: Icon(
                    playingStory == story['id']
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  onPressed: () => playStory(story['id'] as String),
                ),
                title: Text(story['title'] as String),
                childrenPadding: const EdgeInsets.all(20),
                children: [
                  if (story['notice'] != null) Text(story['notice'] as String),
                  SelectableText(story['narration'] as String),
                  for (final source in (story['sources'] as List?) ?? [])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(source as String),
                    ),
                ],
              ),
            for (final m in memories)
              ListTile(
                leading: Icon(
                  m['kind'] == 'video'
                      ? Icons.play_circle_outline
                      : Icons.photo_outlined,
                ),
                title: Text(
                  (m['caption'] as String).isEmpty
                      ? (m['kind'] == 'video' ? 'Video' : 'Photo')
                      : m['caption'] as String,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => media(m),
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    playback++;
    if (playingStory != null) {
      unawaited(speech.stop().catchError((Object _) {}));
    }
    widget.library.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class SharedMediaScreen extends StatefulWidget {
  const SharedMediaScreen({
    super.key,
    required this.shareId,
    required this.media,
    required this.library,
    this.replay = false,
  });
  final String shareId;
  final Map<String, dynamic> media;
  final AccountLibrary library;
  final bool replay;
  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen>
    with WidgetsBindingObserver {
  File? file;
  VideoPlayerController? video;
  String? error;
  Directory? temp;
  Timer? timer;
  bool denied = false;
  late final int generation = widget.library.sessionGeneration;
  bool get valid =>
      mounted &&
      !denied &&
      widget.library.signedIn &&
      generation == widget.library.sessionGeneration;
  @override
  void initState() {
    super.initState();
    widget.library.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => verify());
  }

  void changed() {
    if (!valid) deny();
  }

  void deny() {
    denied = true;
    video?.pause();
    if (mounted) {
      setState(() => error = 'Memory unavailable or access removed.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      verify();
    } else {
      video?.pause();
    }
  }

  Future<void> verify() async {
    if (!valid) return;
    try {
      await widget.library.request(
        'GET',
        '/api/shared-walks/${widget.shareId}',
      );
    } catch (_) {
      deny();
    }
  }

  Future<void> load() async {
    Directory? directory;
    VideoPlayerController? player;
    try {
      directory = await (await getTemporaryDirectory()).createTemp(
        'walkabout-share-',
      );
      temp = directory;
      final local = File(
        '${directory.path}/memory.${widget.media['kind'] == 'video' ? 'mp4' : 'jpg'}',
      );
      await widget.library.transferSharedMedia(
        'GET',
        '/api/shared-walks/${widget.shareId}/media/${widget.media['id']}',
        download: local,
      );
      if (!valid) return;
      if (widget.media['kind'] == 'video') {
        player = VideoPlayerController.file(local);
        await player.initialize();
        if (!valid) {
          await player.dispose();
          player = null;
          return;
        }
      }
      setState(() {
        file = local;
        video = player;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not load this memory.',
        );
      }
    } finally {
      if (!valid && directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Shared memory'),
      actions: [
        IconButton(
          tooltip: 'Close viewer',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    bottomNavigationBar: widget.replay
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () async {
                  await video?.pause();
                  if (context.mounted) Navigator.pop(context, true);
                },
                child: const Text('Continue replay'),
              ),
            ),
          )
        : null,
    body: error != null
        ? Center(child: Text(error!))
        : file == null
        ? const Center(child: CircularProgressIndicator())
        : video == null
        ? InteractiveViewer(
            child: Center(
              child: Image.file(
                file!,
                errorBuilder: (_, _, _) => const Text('Photo unavailable'),
              ),
            ),
          )
        : SharedVideoPlayer(
            controller: video!,
            enabled: valid,
            onToggle: () async {
              await verify();
              if (!valid) return;
              final player = video!;
              if (player.value.isPlaying) {
                await player.pause();
              } else {
                if (player.value.position >= player.value.duration) {
                  await player.seekTo(Duration.zero);
                }
                if (valid) await player.play();
              }
            },
          ),
  );
  @override
  void dispose() {
    timer?.cancel();
    widget.library.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    final player = video;
    final directory = temp;
    unawaited(() async {
      await player?.dispose();
      if (directory != null && await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // Temporary files may already have been removed by an interrupted load.
        }
      }
    }());
    super.dispose();
  }
}
