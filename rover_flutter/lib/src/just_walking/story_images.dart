import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/rover_api_client.dart';
import '../location/rover_location.dart';

class StoryPicture {
  const StoryPicture({
    required this.url,
    required this.caption,
    required this.attribution,
    required this.license,
    required this.licenseUrl,
    required this.sourceUrl,
    this.articleUrl,
    this.isNearby = false,
    this.provider = 'Wikimedia Commons',
    this.isArchive = false,
  });
  final String url, caption, attribution, license, licenseUrl, sourceUrl;
  final String? articleUrl;
  final bool isNearby;
  final String provider;
  final bool isArchive;
  String get kindLabel => isArchive
      ? isNearby
            ? 'Nearby archive material'
            : 'Archive material'
      : isNearby
      ? 'Nearby place'
      : 'Source illustration';

  static StoryPicture? parse(Map<String, dynamic> json) {
    String value(String key) => json[key] is String ? json[key] as String : '';
    bool safe(String key, String host) {
      final uri = Uri.tryParse(value(key));
      return uri != null &&
          uri.scheme == 'https' &&
          uri.host == host &&
          uri.userInfo.isEmpty &&
          uri.port == 443;
    }

    final europeana = value('provider') == 'Europeana';
    final trustedImage = europeana
        ? _europeanaThumbnail(value('url')) &&
              _europeanaSource(value('sourceUrl')) &&
              json['isArchive'] == true
        : safe('url', 'upload.wikimedia.org') &&
              safe('sourceUrl', 'commons.wikimedia.org');
    if (!trustedImage ||
        !safe('licenseUrl', 'creativecommons.org') ||
        !RegExp(
          r'^/(licenses/(by|by-sa)/(1\.0|2\.0|2\.5|3\.0|4\.0)|publicdomain/(zero|mark)/1\.0)/$',
        ).hasMatch(Uri.parse(value('licenseUrl')).path) ||
        value('attribution').isEmpty ||
        value('license').isEmpty) {
      return null;
    }
    return StoryPicture(
      url: value('url'),
      caption: value('caption'),
      attribution: value('attribution'),
      license: value('license'),
      licenseUrl: value('licenseUrl'),
      sourceUrl: value('sourceUrl'),
      articleUrl: supportedPictureSource(value('articleUrl'))
          ? value('articleUrl')
          : null,
      isNearby: json['isNearby'] == true,
      provider: europeana ? 'Europeana' : 'Wikimedia Commons',
      isArchive: europeana,
    );
  }
}

bool _europeanaSource(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      uri.host == 'www.europeana.eu' &&
      RegExp(r'^/(?:[a-z]{2}/)?item/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/?$')
          .hasMatch(uri.path);
}

bool _europeanaThumbnail(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.host != 'api.europeana.eu' ||
      uri.hasFragment) {
    return false;
  }
  if (RegExp(r'^/thumbnail/v3/(200|400)/[a-fA-F0-9]{32}\.jpg$')
      .hasMatch(uri.path)) {
    return !uri.hasQuery;
  }
  if (uri.path != '/thumbnail/v2/url.json') return false;
  final query = uri.queryParameters;
  if (query.length != 3 ||
      query['size'] != 'w400' ||
      query['type'] != 'IMAGE') {
    return false;
  }
  final media = Uri.tryParse(query['uri'] ?? '');
  return media != null &&
      (media.scheme == 'https' || media.scheme == 'http') &&
      media.userInfo.isEmpty &&
      media.host.contains('.') &&
      !RegExp(r'^[0-9.]+$').hasMatch(media.host) &&
      !media.host.endsWith('.local') &&
      !media.host.endsWith('.localhost') &&
      (media.port == 443 && media.scheme == 'https' ||
          media.port == 80 && media.scheme == 'http');
}

bool supportedPictureSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.host == 'www.wikidata.org') {
    return RegExp(r'^/(wiki|entity)/Q[1-9][0-9]*$').hasMatch(uri.path);
  }
  if (_europeanaSource(source)) return true;
  if (uri.host == 'commons.wikimedia.org') {
    return uri.path.startsWith('/wiki/File:');
  }
  return RegExp(r'^[a-z]{2,3}\.wikipedia\.org$').hasMatch(uri.host) &&
      uri.path.startsWith('/wiki/') &&
      !uri.path.substring(6).contains(':');
}

typedef StoryImageLoader = Future<Map<String, dynamic>> Function(
  List<String> sources,
);

class StoryImages extends StatefulWidget {
  const StoryImages({
    super.key,
    required this.sourceUrls,
    this.loader,
    this.nearbyLocation,
    this.compact = false,
  });
  final List<String> sourceUrls;
  final StoryImageLoader? loader;
  final RoverLatLng? nearbyLocation;
  final bool compact;
  @override
  State<StoryImages> createState() => _StoryImagesState();
}

class _StoryImagesState extends State<StoryImages> {
  RoverApiClient? _client;
  List<StoryPicture> _images = [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StoryImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceUrls.join('\n') != widget.sourceUrls.join('\n')) {
      _load();
    } else if (oldWidget.nearbyLocation?.latitude !=
            widget.nearbyLocation?.latitude ||
        oldWidget.nearbyLocation?.longitude !=
            widget.nearbyLocation?.longitude) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _client?.close(force: true);
    _client = null;
    setState(() {
      _loading = true;
      _failed = false;
      _images = [];
    });
    if (widget.sourceUrls.isEmpty && widget.nearbyLocation == null) {
      setState(() => _loading = false);
      return;
    }
    final client = widget.loader == null ? RoverApiClient() : null;
    _client = client;
    try {
      final sources = widget.sourceUrls
          .where(supportedPictureSource)
          .toSet()
          .take(6)
          .toList();
      final json = widget.loader != null
          ? await widget.loader!(widget.sourceUrls)
          : await client!.getStoryImages(
              sources,
              latitude: widget.nearbyLocation?.latitude,
              longitude: widget.nearbyLocation?.longitude,
            );
      if (!mounted || generation != _generation) return;
      final raw = json['images'];
      setState(() {
        _images = raw is List
            ? raw
                  .whereType<Map<String, dynamic>>()
                  .map(StoryPicture.parse)
                  .whereType<StoryPicture>()
                  .take(6)
                  .toList()
            : [];
        _failed = json['status'] == 'unavailable';
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    } finally {
      client?.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    _client?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(
          semanticsLabel: 'Loading story pictures',
        ),
      );
    }
    if (_images.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _failed
                    ? 'Pictures unavailable right now.'
                    : widget.nearbyLocation != null
                    ? 'No sourced pictures available near this stop.'
                    : 'No sourced picture available for this story.',
              ),
            ),
            if (_failed)
              IconButton(
                tooltip: 'Retry pictures',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      );
    }
    return PictureCarousel(pictures: _images, compact: widget.compact);
  }
}

class PictureCarousel extends StatefulWidget {
  const PictureCarousel({
    super.key,
    required this.pictures,
    this.compact = false,
  });
  final List<StoryPicture> pictures;
  final bool compact;
  @override
  State<PictureCarousel> createState() => _PictureCarouselState();
}

class _PictureCarouselState extends State<PictureCarousel> {
  final _pages = PageController();
  int _index = 0;
  @override
  void didUpdateWidget(PictureCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pictures.map((p) => p.url).join() !=
        widget.pictures.map((p) => p.url).join()) {
      _index = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pictures.isEmpty) return const SizedBox.shrink();
    final picture = widget.pictures[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.compact ? 112 : 240,
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.pictures.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final item = widget.pictures[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: 'Enlarge picture ${index + 1}: ${item.caption}',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _PictureScreen(
                          pictures: widget.pictures,
                          initialIndex: index,
                        ),
                      ),
                    ),
                    child: _photo(item),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous picture',
              onPressed: _index > 0
                  ? () => _pages.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_index + 1} / ${widget.pictures.length} - ${picture.kindLabel}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            IconButton(
              tooltip: 'Next picture',
              onPressed: _index < widget.pictures.length - 1
                  ? () => _pages.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            if (widget.compact)
              IconButton(
                tooltip: 'Picture details and credits',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PictureScreen(
                      pictures: widget.pictures,
                      initialIndex: _index,
                    ),
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
          ],
        ),
        if (!widget.compact) ...[
          Text(picture.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
          _Credits(picture: picture),
        ],
      ],
    );
  }
}

Widget _photo(StoryPicture picture) => Image.network(
  picture.url,
  fit: BoxFit.contain,
  semanticLabel: picture.caption,
  loadingBuilder: (_, child, progress) => progress == null
      ? child
      : const Center(child: CircularProgressIndicator()),
  errorBuilder: (_, error, stack) =>
      const Center(child: Text('Picture could not load.')),
);

class _PictureScreen extends StatefulWidget {
  const _PictureScreen({required this.pictures, required this.initialIndex});
  final List<StoryPicture> pictures;
  final int initialIndex;
  @override
  State<_PictureScreen> createState() => _PictureScreenState();
}

class _PictureScreenState extends State<_PictureScreen> {
  late int _index = widget.initialIndex;
  @override
  Widget build(BuildContext context) {
    final picture = widget.pictures[_index];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Story picture'),
        actions: [
          IconButton(
            tooltip: 'Close picture',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                key: ValueKey(_index),
                minScale: 1,
                maxScale: 5,
                child: SizedBox.expand(child: _photo(picture)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous picture',
                  onPressed: _index > 0 ? () => setState(() => _index--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_index + 1} / ${widget.pictures.length}'),
                IconButton(
                  tooltip: 'Next picture',
                  onPressed: _index < widget.pictures.length - 1
                      ? () => setState(() => _index++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .3,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (picture.isArchive) Text(picture.kindLabel),
                    if (picture.isNearby && !picture.isArchive)
                      const Text('Nearby place illustration'),
                    Text(picture.caption),
                    _Credits(picture: picture),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits({required this.picture});
  final StoryPicture picture;
  Future<void> _open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this source.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(picture.attribution, style: Theme.of(context).textTheme.bodySmall),
      Wrap(
        spacing: 8,
        children: [
          if (picture.articleUrl != null &&
              picture.articleUrl != picture.sourceUrl)
            TextButton(
              onPressed: () => _open(context, picture.articleUrl!),
              child: const Text('About this place'),
            ),
          TextButton.icon(
            onPressed: () => _open(context, picture.sourceUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(picture.provider),
          ),
          TextButton(
            onPressed: () => _open(context, picture.licenseUrl),
            child: Text(picture.license),
          ),
        ],
      ),
    ],
  );
}
