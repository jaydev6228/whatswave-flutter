import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'location_map_preview.dart';

/// Defers building [child] until after the first frame so scrolling past many
/// heavy attachments does not block the UI thread in the same frame as layout.
class DeferredHeavyAttachment extends StatefulWidget {
  const DeferredHeavyAttachment({
    required this.placeholder,
    required this.childBuilder,
    super.key,
  });

  final Widget placeholder;
  final Widget Function(BuildContext context) childBuilder;

  @override
  State<DeferredHeavyAttachment> createState() =>
      _DeferredHeavyAttachmentState();
}

class _DeferredHeavyAttachmentState extends State<DeferredHeavyAttachment> {
  bool _shouldBuildChild = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _shouldBuildChild = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldBuildChild) {
      return widget.placeholder;
    }
    return widget.childBuilder(context);
  }
}

/// Fixed footprint for map bubbles so placeholder → real map never changes
/// list height and makes nearby messages jump on send/rebuild.
const double _locationMapBubbleAspectRatio = 1.45;

/// A lightweight map placeholder that upgrades to [LocationMapSnippet] after
/// the first frame -- avoids fetching OSM tiles during fast scroll.
class LazyLocationMapSnippet extends StatelessWidget {
  const LazyLocationMapSnippet({
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: _locationMapBubbleAspectRatio,
      child: DeferredHeavyAttachment(
        key: ValueKey('lazy_map_${latitude}_$longitude'),
        placeholder: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          child: Center(
            child: Icon(
              Icons.location_on_rounded,
              color: theme.colorScheme.primary.withValues(alpha: 0.72),
              size: 40,
            ),
          ),
        ),
        childBuilder: (_) => LocationMapSnippet(
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
  }
}
