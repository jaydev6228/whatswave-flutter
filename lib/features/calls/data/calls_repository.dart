import '../domain/call_history_entry.dart';
import 'calls_overview.dart';

abstract class CallsRepository {
  Future<CallsOverview> fetchOverview();

  Future<List<CallHistoryEntry>> saveHistoryEntry(CallHistoryEntry entry);

  Future<List<CallHistoryEntry>> clearHistory();
}

class CallsRepositoryException implements Exception {
  const CallsRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
