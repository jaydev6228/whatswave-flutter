/// The reasons a user can give when reporting a contact.
///
/// Shared by the report dialog and `firestore.rules`, which rejects a
/// report carrying any other reason -- an open string field on a
/// create-only collection is a free write-anything endpoint.
/// Keep this list and the `reason in [...]` clause in the rules in step.
const List<String> kReportReasons = <String>[
  'Spam or scam',
  'Harassment or bullying',
  'Nudity or sexual content',
  'Violence or threats',
  'Other',
];
