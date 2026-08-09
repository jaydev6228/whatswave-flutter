import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/error_dialog.dart';

/// OpenStreetMap's community tile server -- no API key/billing setup
/// required, unlike Google Maps' own Flutter map widget. `userAgentPackageName`
/// identifies this app to the tile server per OSM's usage policy.
///
/// NOTE for a real store release: OSM's tile.openstreetmap.org is meant for
/// light/development use, not distributed-app-scale traffic -- swap this for
/// a paid tile provider (Mapbox, MapTiler, Stadia Maps) or the official
/// Google Maps Flutter SDK (with a billed API key) before shipping to
/// production users.
const String _osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _osmUserAgentPackageName = 'com.tsjaydevra.whatswave';

/// A small, non-interactive map snippet with a pin -- the chat bubble's
/// preview of a shared location, matching WhatsApp's map-thumbnail style
/// instead of a plain icon+title+details row.
class LocationMapSnippet extends StatelessWidget {
  const LocationMapSnippet({
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final point = ll.LatLng(latitude, longitude);
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: 15,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: _osmTileUrlTemplate,
            userAgentPackageName: _osmUserAgentPackageName,
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MapProvider { apple, google }

/// The full-bleed, real interactive map for a location attachment's full
/// preview -- pannable/zoomable, with a pin and an "Open in Maps" action
/// that launches Apple Maps or Google Maps (a choice on iOS; Google Maps
/// directly on Android, matching each platform's map app conventions).
class LocationMapCanvas extends StatelessWidget {
  const LocationMapCanvas({
    required this.latitude,
    required this.longitude,
    required this.label,
    super.key,
  });

  final double latitude;
  final double longitude;
  final String label;

  Future<void> _launchProvider(BuildContext context, _MapProvider provider) async {
    final query = '$latitude,$longitude';
    final uri = switch (provider) {
      _MapProvider.apple => Uri.parse(
          'https://maps.apple.com/?ll=$query&q=${Uri.encodeComponent(label)}',
        ),
      _MapProvider.google => Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$query',
        ),
    };
    final didLaunch = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!didLaunch && context.mounted) {
      await showErrorDialog(context, 'We could not open Maps for that location.');
    }
  }

  Future<void> _handleOpenInMapsTap(BuildContext context) async {
    if (!Platform.isIOS) {
      await _launchProvider(context, _MapProvider.google);
      return;
    }
    final selected = await showModalBottomSheet<_MapProvider>(
      context: context,
      builder: (sheetContext) => const _MapProviderSheet(),
    );
    if (selected != null && context.mounted) {
      await _launchProvider(context, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = ll.LatLng(latitude, longitude);
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: _osmTileUrlTemplate,
                userAgentPackageName: _osmUserAgentPackageName,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 46,
                    height: 46,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.redAccent,
                      size: 46,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              key: const Key('attachment_viewer_open_in_maps_button'),
              onPressed: () => _handleOpenInMapsTap(context),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open in Maps'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapProviderSheet extends StatelessWidget {
  const _MapProviderSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('open_in_apple_maps_option'),
            leading: const Icon(Icons.map_outlined),
            title: const Text('Apple Maps'),
            onTap: () => Navigator.of(context).pop(_MapProvider.apple),
          ),
          ListTile(
            key: const Key('open_in_google_maps_option'),
            leading: const Icon(Icons.map_outlined),
            title: const Text('Google Maps'),
            onTap: () => Navigator.of(context).pop(_MapProvider.google),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
