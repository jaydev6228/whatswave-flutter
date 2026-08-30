import 'package:flutter/material.dart';

import 'shell_tab_motion.dart';

/// Keeps every tab's state alive while crossfading the active tab in and out.
///
/// [IndexedStack] preserves state but snaps instantly; this gives the softer
/// section change iOS liquid-glass tabs use, without dropping inactive tabs
/// from the tree.
class TabCrossfadeStack extends StatelessWidget {
  const TabCrossfadeStack({
    required this.index,
    required this.children,
    super.key,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = ShellTabMotion.durationFor(
        context, ShellTabMotion.contentCrossfadeDuration);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: index != i,
            child: AnimatedOpacity(
              opacity: index == i ? 1 : 0,
              duration: duration,
              curve: ShellTabMotion.contentCurve,
              child: TickerMode(
                enabled: index == i,
                child: children[i],
              ),
            ),
          ),
      ],
    );
  }
}
