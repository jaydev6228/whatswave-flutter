enum ContactAccessStatus { unknown, granted, limited, denied }

extension ContactAccessStatusX on ContactAccessStatus {
  String get label => switch (this) {
        ContactAccessStatus.unknown => 'Ask every time',
        ContactAccessStatus.granted => 'Allowed',
        ContactAccessStatus.limited => 'Limited to selected contacts',
        ContactAccessStatus.denied => 'Denied',
      };

  /// True for both full and limited access -- i.e. whether there's any
  /// contact data available to show at all, as opposed to [denied]/
  /// [unknown] where there's none.
  bool get hasAnyAccess =>
      this == ContactAccessStatus.granted ||
      this == ContactAccessStatus.limited;
}
