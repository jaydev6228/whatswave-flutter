enum AppLockTimeout {
  immediately(
    label: 'Immediately',
    minutes: 0,
  ),
  oneMinute(
    label: 'After 1 minute',
    minutes: 1,
  ),
  fifteenMinutes(
    label: 'After 15 minutes',
    minutes: 15,
  );

  const AppLockTimeout({
    required this.label,
    required this.minutes,
  });

  final String label;
  final int minutes;

  Duration get duration => Duration(minutes: minutes);

  static AppLockTimeout fromStorage(String? value) {
    for (final timeout in AppLockTimeout.values) {
      if (timeout.name == value) {
        return timeout;
      }
    }
    return AppLockTimeout.immediately;
  }
}
