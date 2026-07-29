enum ContactAccessStatus { unknown, granted, denied }

extension ContactAccessStatusX on ContactAccessStatus {
  String get label => switch (this) {
        ContactAccessStatus.unknown => 'Ask every time',
        ContactAccessStatus.granted => 'Allowed',
        ContactAccessStatus.denied => 'Denied',
      };
}
