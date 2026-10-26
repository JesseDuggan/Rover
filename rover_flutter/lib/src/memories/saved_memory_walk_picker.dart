import 'package:flutter/material.dart';

import '../accounts/account_library.dart';
import '../api/walk_models.dart';
import 'memory_store.dart';

class SavedMemoryWalkPicker extends StatefulWidget {
  const SavedMemoryWalkPicker({super.key, this.library});
  final AccountLibrary? library;
  @override
  State<SavedMemoryWalkPicker> createState() => _SavedMemoryWalkPickerState();
}

class _SavedMemoryWalkPickerState extends State<SavedMemoryWalkPicker> {
  late final library = widget.library ?? AccountLibrary.instance;
  List<LibraryItem> walks = [];
  bool busy = true;
  String? error;
  int epoch = 0;
  late int generation;
  @override
  void initState() {
    super.initState();
    generation = library.sessionGeneration;
    library.addListener(changed);
    load();
  }

  void changed() {
    if (!mounted) return;
    if (!library.signedIn || generation != library.sessionGeneration) {
      epoch++;
      generation = library.sessionGeneration;
      setState(() {
        walks = [];
        busy = false;
        error = null;
      });
    }
  }

  Future<void> load({bool signIn = false}) async {
    final request = ++epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await library.load();
      if (signIn && !library.signedIn) {
        if (await library.signIn() && mounted) await load();
        return;
      }
      if (!mounted || !library.signedIn) return;
      final g = library.sessionGeneration;
      final result = await library.list('walks');
      if (mounted &&
          request == epoch &&
          library.signedIn &&
          g == library.sessionGeneration) {
        setState(() => walks = result);
      }
    } catch (_) {
      if (mounted && request == epoch) {
        setState(() => error = 'Could not load saved walks. Retry');
      }
    } finally {
      if (mounted && request == epoch) setState(() => busy = false);
    }
  }

  void select(LibraryItem item) {
    if (!library.signedIn || generation != library.sessionGeneration) return;
    try {
      final data = item.data['walk'] as Map<String, dynamic>;
      Navigator.pop(
        context,
        MemoryJourney(
          id: data['walkSessionId'] as String,
          route: WalkSession.fromJson(data).toRoam(),
        ),
      );
    } catch (_) {
      setState(() => error = 'This saved walk could not be opened.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attach to saved walk')),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : !library.signedIn
        ? Center(
            child: FilledButton(
              onPressed: () => load(signIn: true),
              child: const Text('Sign in'),
            ),
          )
        : ListView(
            children: [
              if (error != null)
                TextButton(onPressed: load, child: Text(error!)),
              if (error == null && walks.isEmpty)
                const ListTile(title: Text('No saved walks yet')),
              for (final walk in walks)
                ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: Text(walk.name),
                  onTap: () => select(walk),
                ),
            ],
          ),
  );
  @override
  void dispose() {
    library.removeListener(changed);
    super.dispose();
  }
}
