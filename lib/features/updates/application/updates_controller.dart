import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/channel_preview.dart';
import '../../../core/models/status_story.dart';
import '../data/updates_repository.dart';

class UpdatesController extends ChangeNotifier {
  UpdatesController({required UpdatesRepository repository})
      : _repository = repository;

  final UpdatesRepository _repository;

  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isComposingStatus = false;
  String? _errorMessage;
  List<StatusStory> _stories = const <StatusStory>[];
  List<ChannelPreview> _channels = const <ChannelPreview>[];
  final Set<String> _busyStoryIds = <String>{};
  final Map<String, int> _pendingSeenSegmentsByStoryId = <String, int>{};

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isComposingStatus => _isComposingStatus;
  String? get errorMessage => _errorMessage;
  List<StatusStory> get stories => List<StatusStory>.unmodifiable(_stories);
  List<ChannelPreview> get channels =>
      List<ChannelPreview>.unmodifiable(_channels);
  bool get hasContent => _stories.isNotEmpty || _channels.isNotEmpty;

  StatusStory? get myStatus {
    for (final story in _stories) {
      if (story.isMine) {
        return story;
      }
    }
    return null;
  }

  StatusStory? storyForParticipant({
    required String avatarLabel,
    String? name,
  }) {
    final normalizedAvatarLabel = avatarLabel.trim().toLowerCase();
    final normalizedName = name?.trim().toLowerCase() ?? '';

    for (final story in _stories) {
      if (story.isMine) {
        continue;
      }
      if (story.avatarLabel.trim().toLowerCase() == normalizedAvatarLabel) {
        return story;
      }
    }

    if (normalizedName.isEmpty) {
      return null;
    }

    for (final story in _stories) {
      if (story.isMine) {
        continue;
      }
      final storyName = story.name.trim().toLowerCase();
      if (storyName == normalizedName ||
          normalizedName.startsWith('$storyName ') ||
          storyName.startsWith('$normalizedName ')) {
        return story;
      }
    }

    return null;
  }

  List<StatusStory> get recentStories => _stories
      .where((story) => !story.isMine && story.hasUnseenSegments)
      .toList(growable: false);

  List<StatusStory> get viewedStories => _stories
      .where((story) =>
          !story.isMine && story.hasSegments && !story.hasUnseenSegments)
      .toList(growable: false);

  bool isStoryBusy(String storyId) => _busyStoryIds.contains(storyId);

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) {
      return;
    }
    await loadUpdates();
  }

  Future<void> loadUpdates() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final feed = await _repository.fetchUpdates();
      _stories = feed.stories;
      _channels = feed.channels;
      _hasLoaded = true;
    } on UpdatesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load updates right now.';
    }

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> createStatus({
    required StatusStoryType type,
    String? caption,
    String? localMediaPath,
    StatusTextStyle? textStyle,
    StatusMediaTransform? mediaTransform,
    List<StatusMediaOverlayItem>? overlayItems,
    String? emoji,
    List<String>? stickers,
    StatusMusicTrack? musicTrack,
    int? durationMillis,
  }) async {
    if (_isComposingStatus) {
      return false;
    }

    _isComposingStatus = true;
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      _stories = await _repository.createStatus(
        type: type,
        caption: caption,
        localMediaPath: localMediaPath,
        textStyle: textStyle,
        mediaTransform: mediaTransform,
        overlayItems: overlayItems,
        emoji: emoji,
        stickers: stickers,
        musicTrack: musicTrack,
        durationMillis: durationMillis,
      );
      didSucceed = true;
    } on UpdatesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not share that status right now.';
    }

    _isComposingStatus = false;
    notifyListeners();
    return didSucceed;
  }

  Future<void> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) async {
    final story = _stories.cast<StatusStory?>().firstWhere(
          (entry) => entry?.id == storyId,
          orElse: () => null,
        );
    if (story == null || story.isMine || !story.hasSegments) {
      return;
    }

    final normalizedSeenSegments =
        seenSegments.clamp(0, story.totalSegments).toInt();
    if (normalizedSeenSegments <= story.clampedSeenSegments) {
      return;
    }

    _stories = List<StatusStory>.unmodifiable(
      _stories.map((entry) {
        if (entry.id != storyId) {
          return entry;
        }
        return entry.copyWith(seenSegments: normalizedSeenSegments);
      }),
    );
    final currentPendingSeenSegments =
        _pendingSeenSegmentsByStoryId[storyId] ?? 0;
    _pendingSeenSegmentsByStoryId[storyId] = math.max(
      currentPendingSeenSegments,
      normalizedSeenSegments,
    );
    notifyListeners();

    if (_busyStoryIds.contains(storyId)) {
      return;
    }

    await _flushStoryProgress(storyId);
  }

  Future<void> _flushStoryProgress(String storyId) async {
    while (true) {
      final targetSeenSegments = _pendingSeenSegmentsByStoryId[storyId];
      if (targetSeenSegments == null) {
        return;
      }

      _busyStoryIds.add(storyId);
      notifyListeners();

      try {
        final updatedStories = await _repository.markStoryViewed(
          storyId,
          seenSegments: targetSeenSegments,
        );
        _stories = _mergeStoriesPreservingLocalProgress(updatedStories);
        if (_pendingSeenSegmentsByStoryId[storyId] == targetSeenSegments) {
          _pendingSeenSegmentsByStoryId.remove(storyId);
        }
      } on UpdatesRepositoryException catch (error) {
        _errorMessage = error.message;
        _pendingSeenSegmentsByStoryId.remove(storyId);
        break;
      } catch (_) {
        _errorMessage = 'We could not update that story right now.';
        _pendingSeenSegmentsByStoryId.remove(storyId);
        break;
      } finally {
        _busyStoryIds.remove(storyId);
        notifyListeners();
      }

      if (!_pendingSeenSegmentsByStoryId.containsKey(storyId)) {
        return;
      }
    }
  }

  List<StatusStory> _mergeStoriesPreservingLocalProgress(
    List<StatusStory> updatedStories,
  ) {
    final currentStoriesById = <String, StatusStory>{
      for (final story in _stories) story.id: story,
    };
    return List<StatusStory>.unmodifiable(
      updatedStories.map((story) {
        final currentStory = currentStoriesById[story.id];
        if (currentStory == null || story.isMine || !story.hasSegments) {
          return story;
        }

        final mergedSeenSegments = math.max(
          story.clampedSeenSegments,
          currentStory.clampedSeenSegments,
        );
        return story.copyWith(seenSegments: mergedSeenSegments);
      }),
    );
  }

  Future<bool> deleteMyStatusSegment(String segmentId) async {
    final status = myStatus;
    if (status == null || !status.hasSegments || _isComposingStatus) {
      return false;
    }

    _isComposingStatus = true;
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      _stories = await _repository.deleteStatusSegment(
        storyId: status.id,
        segmentId: segmentId,
      );
      didSucceed = true;
    } on UpdatesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not delete that status right now.';
    }

    _isComposingStatus = false;
    notifyListeners();
    return didSucceed;
  }

  Future<bool> clearMyStatuses() async {
    final status = myStatus;
    if (status == null || !status.hasSegments || _isComposingStatus) {
      return false;
    }

    _isComposingStatus = true;
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      _stories = await _repository.clearStory(storyId: status.id);
      didSucceed = true;
    } on UpdatesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not clear your statuses right now.';
    }

    _isComposingStatus = false;
    notifyListeners();
    return didSucceed;
  }
}
