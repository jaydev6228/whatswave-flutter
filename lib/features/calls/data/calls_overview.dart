import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';

class CallsOverview {
  const CallsOverview({
    required this.favorites,
    required this.history,
  });

  final List<CallContact> favorites;
  final List<CallHistoryEntry> history;
}
