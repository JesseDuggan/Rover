import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/location_observation_models.dart';
import '../api/problem_details.dart';

class PhotoIdentificationSheet extends StatefulWidget {
  const PhotoIdentificationSheet({
    required this.photo,
    required this.identify,
    super.key,
  });
  final Uint8List photo;
  final Future<LocationObservationResolution> Function() identify;

  @override
  State<PhotoIdentificationSheet> createState() =>
      _PhotoIdentificationSheetState();
}

class _PhotoIdentificationSheetState extends State<PhotoIdentificationSheet> {
  bool _busy = false;
  LocationObservationResolution? _result;
  String? _error;

  Future<void> _identify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.identify();
      if (mounted) setState(() => _result = result);
    } on RoverApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.statusCode) {
            429 => 'Photo limit reached. Try again later or use sign scanning.',
            503 => 'Photo identification is not available yet. Sign scanning is still available.',
            401 => 'ROVER could not authorize photo identification.',
            _ => 'Could not check this photo. Please try again.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not check this photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final candidates =
        result?.candidates ?? const <LocationObservationCandidate>[];
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .88,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'What is this?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            SizedBox(
              height: 200,
              child: Image.memory(widget.photo, fit: BoxFit.contain),
            ),
            const SizedBox(height: 16),
            if (result == null) ...[
              const Text(
                'Send this photo and your location to ROVER? OpenAI receives the photo and an approximate location to help identify the object. ROVER does not save the photo. Provider retention policies apply. Avoid including people or private information.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _identify,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_search),
                label: Text(_busy ? 'Checking photo...' : 'Send and identify'),
              ),
            ] else if (candidates.isEmpty) ...[
              Text(switch (result.diagnosticCode) {
                'photo_timeout' => 'The check timed out. Try another photo.',
                'photo_provider_unavailable' || 'photo_unavailable' =>
                  'Photo identification is temporarily unavailable.',
                _ => 'No confident nearby match. Try a closer photo of a name or plaque.',
              }),
            ] else ...[
              const Text(
                'Possible matches, not confirmed identities. Compare the name and address with what you see.',
              ),
              for (final candidate in candidates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(candidate.place.name),
                  subtitle: Text(
                    candidate.place.address ?? 'Nearby sourced place',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(candidate.place.name),
                        content: const Text(
                          'Is this the place in your photo? Confirm to select it, then use Hear story.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Not this one'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Confirm place'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(context, candidate);
                    }
                  },
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
          ],
        ),
      ),
    );
  }
}
