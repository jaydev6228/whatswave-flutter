import 'package:flutter/material.dart';

class WhatsWaveScrollBehavior extends MaterialScrollBehavior {
  const WhatsWaveScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (getPlatform(context)) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return child;
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return super.buildOverscrollIndicator(context, child, details);
    }
  }
}
