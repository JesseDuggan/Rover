
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'memory_store.dart';

class MemoryThumbnail extends StatefulWidget {
  const MemoryThumbnail({super.key, required this.memory});
  final WalkMemory memory;
  @override
  State<MemoryThumbnail> createState() => _MemoryThumbnailState();
}

class _MemoryThumbnailState extends State<MemoryThumbnail> {
  static const channel = MethodChannel('ai.myrover.rover/memories');
  // Bounded, memory-only cache. No additional copies of private videos on disk.
  static final cache = <String, Future<Uint8List?>>{};
  Future<Uint8List?>? thumbnail;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(MemoryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.file.path != widget.memory.file.path) load();
  }

  void load() {
    if (!widget.memory.isVideo) {
      thumbnail = null;
      return;
    }
    final path = widget.memory.file.path;
    if (!cache.containsKey(path)) {
      if (cache.length >= 32) cache.remove(cache.keys.first);
      cache[path] = frame(path);
    }
    thumbnail = cache[path];
  }

  static Future<Uint8List?> frame(String path) async {
    try {
      return await channel.invokeMethod<Uint8List>('thumbnail', {'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Widget fallback() => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.videocam_outlined, size: 40)),
  );
  @override
  Widget build(BuildContext context) => widget.memory.isVideo
      ? Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbnail,
              builder: (context, snapshot) => snapshot.data == null
                  ? fallback()
                  : Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: false,
                      errorBuilder: (_, _, _) => fallback(),
                    ),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.play_arrow, size: 32, color: Colors.white),
                ),
              ),
            ),
          ],
        )
      : Image.file(
          widget.memory.file,
          fit: BoxFit.cover,
          cacheWidth: 480,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
}
