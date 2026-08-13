/// Short timestamps for community list and home rows.
String formatCommunityTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTimestamp =
      DateTime(timestamp.year, timestamp.month, timestamp.day);
  final dayDifference = startOfToday.difference(startOfTimestamp).inDays;

  if (dayDifference == 0) {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final meridiem = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${timestamp.minute.toString().padLeft(2, '0')} $meridiem';
  }
  if (dayDifference == 1) {
    return 'Yesterday';
  }
  if (dayDifference < 7) {
    const weekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return weekdays[timestamp.weekday - 1];
  }
  return '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
}

String formatCommunityRelativeTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTimestamp =
      DateTime(timestamp.year, timestamp.month, timestamp.day);
  final dayDifference = startOfToday.difference(startOfTimestamp).inDays;

  final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
  final meridiem = timestamp.hour >= 12 ? 'PM' : 'AM';
  final timeLabel =
      '$hour:${timestamp.minute.toString().padLeft(2, '0')} $meridiem';

  if (dayDifference == 0) {
    return 'Today, $timeLabel';
  }
  if (dayDifference == 1) {
    return 'Yesterday, $timeLabel';
  }
  return '${timestamp.month}/${timestamp.day}, $timeLabel';
}
