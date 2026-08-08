import '../../../core/sample/demo_data.dart';
import '../domain/call_contact.dart';
import '../domain/call_history_entry.dart';
import 'calls_overview.dart';
import 'calls_repository.dart';

class FakeCallsRepository implements CallsRepository {
  FakeCallsRepository({
    List<CallContact>? initialFavorites,
    List<CallHistoryEntry>? initialHistory,
    this.latency = const Duration(milliseconds: 180),
    this.failFetchOnce = false,
    this.failSaveNext = false,
    this.failClearNext = false,
    this.failDeleteNext = false,
  })  : _favorites = List<CallContact>.unmodifiable(
          (initialFavorites ?? DemoData.buildCallFavorites())
              .map((contact) => contact.copyWith()),
        ),
        _history = _cloneHistory(
          _sortHistory(initialHistory ?? DemoData.buildCallHistory()),
        );

  final Duration latency;
  bool failFetchOnce;
  bool failSaveNext;
  bool failClearNext;
  bool failDeleteNext;

  final List<CallContact> _favorites;
  List<CallHistoryEntry> _history;

  Future<void> _wait() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }

  @override
  Future<CallsOverview> fetchOverview() async {
    await _wait();
    if (failFetchOnce) {
      failFetchOnce = false;
      throw const CallsRepositoryException('Transient calls failure');
    }

    return CallsOverview(
      favorites: List<CallContact>.unmodifiable(
        _favorites.map((contact) => contact.copyWith()),
      ),
      history: _cloneHistory(_history),
    );
  }

  @override
  Future<List<CallHistoryEntry>> saveHistoryEntry(
      CallHistoryEntry entry) async {
    await _wait();
    if (failSaveNext) {
      failSaveNext = false;
      throw const CallsRepositoryException(
        'We could not update recent calls right now.',
      );
    }

    _history = _cloneHistory(
      _sortHistory([
        entry,
        ..._history.where((existing) => existing.id != entry.id),
      ]),
    );
    return _cloneHistory(_history);
  }

  @override
  Future<List<CallHistoryEntry>> deleteHistoryEntry(String entryId) async {
    await _wait();
    if (failDeleteNext) {
      failDeleteNext = false;
      throw const CallsRepositoryException(
        'We could not delete that call right now.',
      );
    }

    _history = _cloneHistory(
      _history.where((entry) => entry.id != entryId).toList(growable: false),
    );
    return _cloneHistory(_history);
  }

  @override
  Future<List<CallHistoryEntry>> clearHistory() async {
    await _wait();
    if (failClearNext) {
      failClearNext = false;
      throw const CallsRepositoryException(
        'We could not clear recent calls right now.',
      );
    }

    _history = const <CallHistoryEntry>[];
    return const <CallHistoryEntry>[];
  }

  static List<CallHistoryEntry> _cloneHistory(List<CallHistoryEntry> history) {
    return List<CallHistoryEntry>.unmodifiable(
      history.map((entry) => entry.copyWith()),
    );
  }

  static List<CallHistoryEntry> _sortHistory(List<CallHistoryEntry> history) {
    final sorted = List<CallHistoryEntry>.from(history);
    sorted.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return sorted;
  }
}
