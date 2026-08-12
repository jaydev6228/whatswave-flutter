import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../app/theme/app_palette.dart';
import '../../../core/permissions/device_location_service.dart';
import '../domain/chat_attachment.dart';
import 'widgets/location_map_preview.dart'
    show osmTileUrlTemplate, osmUserAgentPackageName;

/// Attachment + optional caption chosen on the location preview screen.
class LocationSendDraft {
  const LocationSendDraft({
    required this.attachment,
    required this.caption,
  });

  final ChatAttachment attachment;
  final String? caption;
}

/// WhatsApp-style location picker: pan the map to choose a pin, optionally
/// snap to the device's current fix, add a caption, then send. The
/// conversation composer's draft text is intentionally *not* imported here.
class LocationSendPreviewScreen extends StatefulWidget {
  const LocationSendPreviewScreen({
    required this.threadId,
    this.locationService,
    super.key,
  });

  final String threadId;
  final DeviceLocationService? locationService;

  @override
  State<LocationSendPreviewScreen> createState() =>
      _LocationSendPreviewScreenState();
}

class _LocationSendPreviewScreenState extends State<LocationSendPreviewScreen> {
  static const ll.LatLng _fallbackCenter = ll.LatLng(37.7879, -122.4075);

  final MapController _mapController = MapController();
  final TextEditingController _captionController = TextEditingController();

  ll.LatLng _selectedCenter = _fallbackCenter;
  bool _isLocating = false;
  String? _statusMessage;

  DeviceLocationService get _locationService =>
      widget.locationService ?? GeolocatorDeviceLocationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_centerOnCurrentLocation(silent: true));
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _centerOnCurrentLocation({required bool silent}) async {
    if (_isLocating) {
      return;
    }
    setState(() {
      _isLocating = true;
      if (!silent) {
        _statusMessage = 'Finding your location…';
      }
    });

    try {
      if (widget.locationService != null) {
        final fix = await _locationService.getCurrentLocation();
        if (!mounted) {
          return;
        }
        final point = ll.LatLng(fix.latitude, fix.longitude);
        setState(() {
          _selectedCenter = point;
          _statusMessage = null;
        });
        _mapController.move(point, _mapController.camera.zoom);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          setState(
            () => _statusMessage =
                'Allow location access to share your current location.',
          );
        }
        return;
      }

      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        if (!silent && mounted) {
          setState(
            () => _statusMessage =
                'Turn on location services to use your current location.',
          );
        }
        return;
      }

      final fix = await _locationService.getCurrentLocation();
      if (!mounted) {
        return;
      }
      final point = ll.LatLng(fix.latitude, fix.longitude);
      setState(() {
        _selectedCenter = point;
        _statusMessage = null;
      });
      _mapController.move(point, _mapController.camera.zoom);
    } on DeviceLocationException catch (error) {
      if (!silent && mounted) {
        setState(() => _statusMessage = error.message);
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(
          () => _statusMessage =
              'We could not get your current location right now.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _onMapMoved(MapEvent event) {
    if (event is! MapEventMove && event is! MapEventRotate) {
      return;
    }
    final center = _mapController.camera.center;
    if (center.latitude == _selectedCenter.latitude &&
        center.longitude == _selectedCenter.longitude) {
      return;
    }
    setState(() {
      _selectedCenter = center;
      _statusMessage = null;
    });
  }

  Future<void> _sendCurrentLocationPin() async {
    await _centerOnCurrentLocation(silent: false);
    if (!mounted || _isLocating) {
      return;
    }
    _confirmSend(isCurrentLocation: true);
  }

  void _confirmSend({required bool isCurrentLocation}) {
    final caption = _captionController.text.trim();
    final attachment = ChatAttachment(
      id: '${widget.threadId}-location-${DateTime.now().microsecondsSinceEpoch}',
      type: ChatAttachmentType.location,
      title: isCurrentLocation ? 'Current location' : 'Location',
      details: 'Tap to open in Maps',
      tintColor: AppPalette.rose,
      latitude: _selectedCenter.latitude,
      longitude: _selectedCenter.longitude,
    );
    Navigator.of(context).pop(
      LocationSendDraft(
        attachment: attachment,
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      key: const Key('location_send_preview_screen'),
      appBar: AppBar(
        leading: IconButton(
          key: const Key('location_send_preview_close_button'),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Send location'),
        actions: [
          TextButton(
            key: const Key('location_send_preview_send_button'),
            onPressed: () => _confirmSend(isCurrentLocation: false),
            child: const Text('Send'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedCenter,
                    initialZoom: 15,
                    onMapEvent: _onMapMoved,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: osmTileUrlTemplate,
                      userAgentPackageName: osmUserAgentPackageName,
                    ),
                  ],
                ),
                IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.location_on_rounded,
                      color: theme.colorScheme.error,
                      size: 44,
                    ),
                  ),
                ),
                if (_isLocating)
                  const Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_statusMessage != null) ...[
                    Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    key: const Key('location_send_preview_caption_field'),
                    controller: _captionController,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a caption (optional)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('location_send_current_location_button'),
                    onPressed: _isLocating ? null : _sendCurrentLocationPin,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('Send your current location'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('location_send_selected_location_button'),
                    onPressed: () => _confirmSend(isCurrentLocation: false),
                    child: const Text('Send this location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
