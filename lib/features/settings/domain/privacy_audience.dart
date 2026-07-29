enum PrivacyAudience {
  everyone('Everyone'),
  contacts('My contacts'),
  nobody('Nobody');

  const PrivacyAudience(this.label);

  final String label;

  static PrivacyAudience fromStorage(String? value) {
    for (final audience in PrivacyAudience.values) {
      if (audience.name == value) {
        return audience;
      }
    }
    return PrivacyAudience.contacts;
  }
}
