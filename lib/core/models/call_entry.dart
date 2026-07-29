import 'package:flutter/material.dart';

class CallEntry {
  const CallEntry({
    required this.name,
    required this.timeLabel,
    required this.avatarLabel,
    required this.accentColor,
    this.isVideo = false,
    this.isMissed = false,
    this.isOutgoing = true,
  });

  final String name;
  final String timeLabel;
  final String avatarLabel;
  final Color accentColor;
  final bool isVideo;
  final bool isMissed;
  final bool isOutgoing;
}
