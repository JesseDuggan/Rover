import 'package:flutter/material.dart';

import '../accounts/account_library.dart';
import '../memories/memory_store.dart';

class RetryShareScreen extends StatefulWidget {
  const RetryShareScreen({
    super.key,
    required this.id,
    required this.library,
    this.store,
  });
  final String id;
  final AccountLibrary library;
  final MemoryStore? store;
  @override
  State<RetryShareScreen> createState() => _RetryShareScreenState();
}

class _RetryShareScreenState extends State<RetryShareScreen> {
  late final store = widget.store ?? MemoryStore();
  late final generation = widget.library.sessionGeneration;
  Map<String, dynamic>? draft;
  List<WalkMemory> files = [];
  Map<String, String> selected = {};
  String? error, progress;
  bool busy = true;
  bool get valid =>
      mounted &&
      widget.library.signedIn &&
      widget.library.sessionGeneration == generation;
  void check() {
    if (!valid) {
      throw const LibraryException('Account changed. Upload stopped.');
    }
  }

  @override
  void initState() {
    super.initState();
    widget.library.addListener(changed);
    load();
  }

  void changed() {
    if (!valid && mounted) {
      setState(() {
        draft = null;
        files = [];
        selected = {};
        error = 'Sign in to the original account to retry this upload.';
      });
    }
  }

  @override
  void dispose() {
    widget.library.removeListener(changed);
    super.dispose();
  }

  List<Map> get missing {
    final uploaded = (draft?['uploadedMediaIds'] as List?) ?? [];
    return ((draft?['media'] as List?) ?? [])
        .cast<Map>()
        .where((m) => !uploaded.contains(m['id']))
        .toList();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.library.request(
        'GET',
        '/api/shared-walks/${widget.id}',
      );
      check();
      if (value['owned'] != true) {
        throw const LibraryException('Only the sender can retry an upload.');
      }
      if (value['status'] == 'published') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (value['status'] != 'draft') {
        throw const LibraryException(
          'This share is private. Create a new share instead.',
        );
      }
      if (value['uploadedMediaIds'] is! List) {
        throw const LibraryException(
          'Upload recovery needs the updated server.',
        );
      }
      final local = await store.list();
      final mapping = await store.uploadFiles(widget.id);
      check();
      setState(() {
        draft = Map<String, dynamic>.from(value as Map);
        files = local;
        selected = mapping;
      });
    } catch (e) {
      if (valid) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Could not load this draft. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retry() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finish sharing this walk?'),
        content: const Text(
          'Upload the missing files and share with the original audience. The original story and location choices stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retry upload'),
          ),
        ],
      ),
    );
    if (yes != true || !valid) return;
    setState(() {
      busy = true;
      error = null;
      progress = 'Checking upload';
    });
    try {
      final latest = await widget.library.request(
        'GET',
        '/api/shared-walks/${widget.id}',
      );
      check();
      if (latest['owned'] != true) {
        throw const LibraryException('Only the sender can retry an upload.');
      }
      if (latest['status'] == 'published') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (latest['status'] != 'draft' || latest['uploadedMediaIds'] is! List) {
        throw const LibraryException(
          'This draft changed. Refresh before retrying.',
        );
      }
      draft = Map<String, dynamic>.from(latest as Map);
      final pending = missing;
      final fresh = await store.list();
      check();
      final chosen = <WalkMemory>[];
      for (final media in pending) {
        final matches = fresh.where(
          (m) =>
              m.id == selected[media['id']] &&
              !m.details.sharingLocked &&
              m.isVideo == (media['kind'] == 'video'),
        );
        if (matches.isEmpty) {
          throw const LibraryException(
            'Choose an available file for each missing memory. Private memories cannot be uploaded.',
          );
        }
        chosen.add(matches.first);
      }
      for (final m in fresh) {
        if (m.details.sharingLocked && selected.values.contains(m.id)) {
          throw const LibraryException(
            'A memory was marked private. Delete this draft and create a new share.',
          );
        }
      }
      await store.saveUploadFiles(widget.id, selected);
      check();
      for (var i = 0; i < pending.length; i++) {
        setState(
          () => progress =
              'Uploading missing memory ${i + 1} of ${pending.length}',
        );
        await widget.library.transferSharedMedia(
          'PUT',
          '/api/shared-walks/${widget.id}/media/${pending[i]['id']}',
          upload: chosen[i].file,
        );
        check();
      }
      setState(() => progress = 'Finishing share');
      await widget.library.request(
        'POST',
        '/api/shared-walks/${widget.id}/publish',
      );
      check();
      try { await store.forgetUpload(widget.id); } catch (_) {}
      if (mounted && valid) Navigator.pop(context, true);
    } catch (e) {
      if (valid) {
        setState(
          () => error = e is LibraryException
              ? e.message
              : 'Upload interrupted. Your draft is kept; try again.',
        );
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: progress == null,
    child: Scaffold(
      appBar: AppBar(title: const Text('Retry upload')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (progress != null) Text(progress!),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!),
            ),
          if (!busy && draft == null && valid)
            TextButton(onPressed: load, child: const Text('Refresh draft')),
          if (draft != null) ...[
            Text(
              draft!['title'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${(draft!['uploadedMediaIds'] as List).length} of ${(draft!['media'] as List).length} memories uploaded',
            ),
            const Text(
              'Not visible to friends until sharing finishes. Unfinished drafts expire after 24 hours.',
            ),
            for (final media in missing)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${media['id']}:${selected[media['id']]}'),
                  isExpanded: true,
                  initialValue:
                      files.any(
                        (m) =>
                            m.id == selected[media['id']] &&
                            !m.details.sharingLocked &&
                            m.isVideo == (media['kind'] == 'video'),
                      )
                      ? selected[media['id']]
                      : null,
                  decoration: InputDecoration(
                    labelText: (media['caption'] as String?)?.isNotEmpty == true
                        ? media['caption'] as String
                        : 'Missing ${media['kind']}',
                  ),
                  hint: const Text('Choose original memory on this phone'),
                  items: [
                    for (final m in files.where(
                      (m) =>
                          !m.details.sharingLocked &&
                          m.isVideo == (media['kind'] == 'video'),
                    ))
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.details.caption.isNotEmpty
                              ? m.details.caption
                              : m.id,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          if (value != null) {
                            selected[media['id'] as String] = value;
                          }
                        }),
                ),
              ),
            FilledButton.icon(
              onPressed: busy || !valid ? null : retry,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Retry upload'),
            ),
          ],
        ],
      ),
    ),
  );
}
