import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/hotel_rate_models.dart';
import '../api/hotel_rate_repository.dart';
import '../api/problem_details.dart';
import '../diagnostics/field_diagnostics.dart';
import '../diagnostics/performance_diagnostics.dart';
import '../location/rover_location.dart';

class HotelRateSearchSheet extends StatefulWidget {
  const HotelRateSearchSheet({
    required this.hotelName,
    required this.placeId,
    required this.coordinates,
    required this.repository,
    super.key,
  });

  final String hotelName;
  final String? placeId;
  final RoverLatLng coordinates;
  final HotelRateRepository repository;

  @override
  State<HotelRateSearchSheet> createState() => _HotelRateSearchSheetState();
}

class _HotelRateSearchSheetState extends State<HotelRateSearchSheet> {
  late DateTime _checkInDate;
  late DateTime _checkOutDate;
  int _adults = 2;
  int _rooms = 1;
  bool _searching = false;
  HotelRateSearchResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day);
    _checkOutDate = _checkInDate.add(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hotel_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.hotelName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DateControl(
                  label: 'Check-in',
                  value: _checkInDate,
                  onPressed: _pickCheckIn,
                ),
                _DateControl(
                  label: 'Check-out',
                  value: _checkOutDate,
                  onPressed: _pickCheckOut,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _CountControl(
                  label: 'Adults',
                  value: _adults,
                  onDecrease: _adults > 1 && _adults > _rooms
                      ? () => setState(() => _adults--)
                      : null,
                  onIncrease: _adults < 12
                      ? () => setState(() => _adults++)
                      : null,
                ),
                _CountControl(
                  label: 'Rooms',
                  value: _rooms,
                  onDecrease: _rooms > 1
                      ? () => setState(() => _rooms--)
                      : null,
                  onIncrease: _rooms < 6 && _rooms < _adults
                      ? () => setState(() => _rooms++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? 'Checking...' : 'Search rates'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ResultNotice(message: _error!, isError: true),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _HotelRateResults(result: _result!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickCheckIn() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _checkInDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _checkInDate = selected;
      if (!_checkOutDate.isAfter(selected)) {
        _checkOutDate = selected.add(const Duration(days: 1));
      }
      _result = null;
      _error = null;
    });
  }

  Future<void> _pickCheckOut() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _checkOutDate,
      firstDate: _checkInDate.add(const Duration(days: 1)),
      lastDate: _checkInDate.add(const Duration(days: 30)),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _checkOutDate = selected;
      _result = null;
      _error = null;
    });
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _result = null;
      _error = null;
    });
    final started = DateTime.now();
    try {
      final result = await widget.repository.search(
        HotelRateSearchRequest(
          hotelName: widget.hotelName,
          placeId: widget.placeId,
          latitude: widget.coordinates.latitude,
          longitude: widget.coordinates.longitude,
          checkInDate: _checkInDate,
          checkOutDate: _checkOutDate,
          adults: _adults,
          rooms: _rooms,
        ),
      );
      PerformanceDiagnostics.instance.record(
        'camera hotel rate search',
        DateTime.now().difference(started),
      );
      FieldDiagnostics.instance.record(
        'commerce',
        'hotel rate search ${result.status.name}; offers ${result.offers.length}',
      );
      if (mounted) {
        setState(() => _result = result);
      }
    } on RoverApiException catch (exception) {
      PerformanceDiagnostics.instance.record(
        'camera hotel rate search failed',
        DateTime.now().difference(started),
        success: false,
      );
      FieldDiagnostics.instance.record(
        'commerce',
        'hotel rate search failed HTTP ${exception.statusCode ?? 0}',
      );
      if (mounted) {
        setState(
          () => _error =
              'Live rates could not be checked right now. ${exception.message}',
        );
      }
    } catch (exception) {
      PerformanceDiagnostics.instance.record(
        'camera hotel rate search failed',
        DateTime.now().difference(started),
        success: false,
      );
      FieldDiagnostics.instance.record(
        'commerce',
        'hotel rate search failed ${exception.runtimeType}',
      );
      if (mounted) {
        setState(() => _error = 'Live rates could not be checked right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }
}

class _DateControl extends StatelessWidget {
  const _DateControl({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final DateTime value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label ${value.month}/${value.day}/${value.year}'),
    );
  }
}

class _CountControl extends StatelessWidget {
  const _CountControl({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: $value'),
        IconButton(
          onPressed: onDecrease,
          icon: const Icon(Icons.remove),
          tooltip: 'Remove $label',
        ),
        IconButton(
          onPressed: onIncrease,
          icon: const Icon(Icons.add),
          tooltip: 'Add $label',
        ),
      ],
    );
  }
}

class _HotelRateResults extends StatelessWidget {
  const _HotelRateResults({required this.result});

  final HotelRateSearchResult result;

  @override
  Widget build(BuildContext context) {
    if (result.offers.isEmpty) {
      final disclosure = result.disclosure.trim();
      return _ResultNotice(
        message: disclosure.isEmpty
            ? result.message
            : '${result.message}\n\n$disclosure',
        isError: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rates', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final offer in result.offers) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${offer.currency} ${offer.totalAmount.toStringAsFixed(2)} total',
            ),
            subtitle: Text(
              '${offer.roomName} - ${offer.providerName}\n'
              '${offer.includesTaxesAndFees ? 'Taxes and fees included' : 'Taxes and fees may be extra'}',
            ),
            trailing: offer.bookingUrl.isEmpty
                ? null
                : IconButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: offer.bookingUrl),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Booking link copied.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.link),
                    tooltip: 'Copy booking link',
                  ),
          ),
          if (offer.disclosure.isNotEmpty)
            Text(
              offer.disclosure,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Divider(),
        ],
        if (result.disclosure.isNotEmpty)
          Text(result.disclosure, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ResultNotice extends StatelessWidget {
  const _ResultNotice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    );
  }
}
