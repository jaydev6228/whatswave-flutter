import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/channel_preview.dart';
import '../../../core/models/status_story.dart';
import '../../../core/models/story_viewer.dart';
import '../../../core/utils/user_profile_lookup.dart';
import 'status_media_store.dart';
import 'updates_repository.dart';

/// Firestore-backed [UpdatesRepository].
///
/// Each user's "My Status" is one document at `statusStories/{uid}`, keyed
/// by their own Firebase Auth uid -- this mirrors FakeUpdatesRepository's
/// single shared 'my-status' story exactly, just with a real per-user id
/// instead of a literal string every demo user shared.
///
/// Media uploads to Firebase Storage (FirebaseStatusMediaStore) so a
/// story's photo/video displays for every viewer, not just the device that
/// created it -- pass mediaStore: LocalStatusMediaStore() instead to keep
/// media device-local only (e.g. for a Storage-less dev environment).
///
/// Visibility is scoped to people you've chatted with at least once: a
/// story is only readable by its owner or someone who shares a
/// `chatThreads` document with them (see firestore.rules, which checks
/// this via the same deterministic sorted-uid thread id
/// `FirestoreChatRepository.startThread` uses). Firestore can't filter a
/// blanket collection query by that rule, so this repository fetches the
/// caller's chat partner uids first, then reads each of their (and its
/// own) `statusStories/{uid}` document individually instead of scanning
/// the whole collection.
///
/// Seen-progress is per-viewer, stored at
/// `statusStories/{ownerUid}/views/{viewerUid}` (see [markStoryViewed] and
/// [_storyFromDoc]) rather than as a field on the story doc itself -- the
/// story doc is owner-write-only, so a shared field could never actually
/// persist another viewer's progress; every cross-user "seen" write
/// silently failed, which is why the ring reverted to unseen once the app
/// restarted and re-read the untouched story doc.
class FirestoreUpdatesRepository implements UpdatesRepository {
  FirestoreUpdatesRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
    StatusMediaStore? mediaStore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _mediaStore = mediaStore ?? FirebaseStatusMediaStore();

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final StatusMediaStore _mediaStore;

  CollectionReference<Map<String, dynamic>> get _storiesRef =>
      _firestore.collection('statusStories');

  CollectionReference<Map<String, dynamic>> get _threadsRef =>
      _firestore.collection('chatThreads');

  String get _requireCurrentUid {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw const UpdatesRepositoryException(
        'Sign in again to load your updates.',
      );
    }
    return uid;
  }

  /// The uids of everyone the caller has an existing 1:1 chat thread with --
  /// i.e. everyone whose story is visible to them, besides themself. See
  /// firestore.rules (statusStories read rule) and
  /// FirestoreChatRepository.startThread for why group members are excluded:
  /// visibility is checked via exists() on the deterministic sorted-uid
  /// chatThreads id, which only 1:1 threads use.
  Future<Set<String>> _chatPartnerUids(String uid) async {
    final snapshot =
        await _threadsRef.where('participantUids', arrayContains: uid).get();
    final partners = <String>{};
    for (final doc in snapshot.docs) {
      partners.addAll(_directMessagePartnerUids(doc.data(), uid));
    }
    return partners;
  }

  /// Partner uids from a single thread doc, or empty when the thread is a
  /// group (or otherwise not a 1:1 DM). Group membership alone does not
  /// grant statusStories read access in firestore.rules.
  Iterable<String> _directMessagePartnerUids(
    Map<String, dynamic> threadData,
    String uid,
  ) {
    if (threadData['isGroup'] == true) {
      return const <String>[];
    }
    final participantUids =
        (threadData['participantUids'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
    if (participantUids.length != 2) {
      return const <String>[];
    }
    return participantUids.where((entry) => entry != uid);
  }

  @override
  Stream<UpdatesFeed> watchUpdates() {
    final uid = _requireCurrentUid;
    final controller = StreamController<UpdatesFeed>.broadcast();
    final storySubscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final latestStories = <String, StatusStory>{};

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add(
        UpdatesFeed(
          stories: latestStories.values.toList(growable: false),
          channels: const <ChannelPreview>[],
        ),
      );
    }

    void watchStoryFor(String ownerUid) {
      if (storySubscriptions.containsKey(ownerUid)) {
        return;
      }
      storySubscriptions[ownerUid] =
          _storiesRef.doc(ownerUid).snapshots().listen((doc) async {
        final story = await _storyFromDoc(doc, currentUid: uid);
        if (story == null) {
          latestStories.remove(ownerUid);
        } else {
          latestStories[ownerUid] = story;
        }
        emit();
      });
    }

    watchStoryFor(uid);
    final threadsSubscription = _threadsRef
        .where('participantUids', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        for (final participantUid in _directMessagePartnerUids(doc.data(), uid)) {
          watchStoryFor(participantUid);
        }
      }
    });

    controller.onCancel = () async {
      await threadsSubscription.cancel();
      for (final subscription in storySubscriptions.values) {
        await subscription.cancel();
      }
    };

    return controller.stream;
  }

  @override
  Future<UpdatesFeed> fetchUpdates() async {
    final uid = _requireCurrentUid;
    try {
      final partnerUids = await _chatPartnerUids(uid);
      final docs = await Future.wait(
        <String>{uid, ...partnerUids}
            .map((ownerUid) => _storiesRef.doc(ownerUid).get()),
      );
      final resolvedStories = await Future.wait(
        docs.map((doc) => _storyFromDoc(doc, currentUid: uid)),
      );
      final stories =
          resolvedStories.whereType<StatusStory>().toList(growable: false);

      // Channels/discovery aren't part of this Firestore slice yet.
      return UpdatesFeed(stories: stories, channels: const <ChannelPreview>[]);
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'We could not load updates right now.',
      );
    }
  }

  @override
  Future<List<StatusStory>> createStatus({
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
    final uid = _requireCurrentUid;

    final normalizedCaption = caption?.trim() ?? '';
    final normalizedEmoji = emoji?.trim();
    final normalizedStickers = List<String>.unmodifiable(
      (stickers ?? const <String>[])
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty),
    );
    final normalizedOverlayItems = List<StatusMediaOverlayItem>.unmodifiable(
      overlayItems == null || overlayItems.isEmpty
          ? _legacyOverlayItems(
              caption: normalizedCaption,
              textStyle: textStyle,
              emoji: normalizedEmoji,
              stickers: normalizedStickers,
              musicTrack: musicTrack,
            )
          : overlayItems,
    );
    final previewText = normalizedCaption.isEmpty
        ? switch (type) {
            StatusStoryType.text => 'Shared a fresh text update',
            StatusStoryType.photo => 'Shared a new photo update',
            StatusStoryType.video => 'Shared a new video update',
          }
        : normalizedCaption;

    try {
      final docRef = _storiesRef.doc(uid);
      final existingDoc = await docRef.get();
      final currentStory = existingDoc.exists
          ? (await _storyFromDoc(existingDoc, currentUid: uid) ??
              _freshMyStatus(uid))
          : _freshMyStatus(uid);

      final priorLiveSegments = _segmentsFor(currentStory);
      // Every prior segment has already expired (or this is the first-ever
      // post) -- this is a fresh story cycle, so any views/likes recorded
      // against the old, now-gone content shouldn't carry over and inflate
      // the new post's viewer count. The `segments` field itself already
      // self-heals this way (an expired segment silently drops out of the
      // array the next time it's rewritten -- see _storyFromDoc's
      // liveSegments filter), but the `views` subcollection is separate and
      // was never being cleaned up alongside it.
      if (priorLiveSegments.isEmpty) {
        await _clearViews(docRef);
      }

      final storedMediaPath =
          await _maybeImportMedia(type: type, localMediaPath: localMediaPath);
      final postedAt = DateTime.now();
      final nextSegments = List<StatusStorySegment>.unmodifiable([
        ...priorLiveSegments,
        StatusStorySegment(
          id: 'status-${postedAt.microsecondsSinceEpoch}',
          type: type,
          previewText: previewText,
          localMediaPath: storedMediaPath,
          mediaTransform: mediaTransform ?? const StatusMediaTransform(),
          durationMillis: durationMillis,
          textStyle: type == StatusStoryType.text
              ? (textStyle ?? const StatusTextStyle())
              : textStyle,
          emoji: normalizedEmoji?.isEmpty == true ? null : normalizedEmoji,
          stickers: normalizedStickers,
          musicTrack: musicTrack,
          overlayItems: normalizedOverlayItems,
          postedAt: postedAt,
        ),
      ]);

      final updatedStory = currentStory.copyWith(
        type: type,
        previewText: previewText,
        timeLabel: 'Just now',
        totalSegments: nextSegments.length,
        seenSegments: 0,
        segments: nextSegments,
        postedAt: postedAt,
      );

      await docRef.set(updatedStory.toJson());
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'We could not share that status right now.',
      );
    }

    return (await fetchUpdates()).stories;
  }

  @override
  Future<List<StatusStory>> markStoryViewed(
    String storyId, {
    required int seenSegments,
  }) async {
    final uid = _requireCurrentUid;

    try {
      final doc = await _storiesRef.doc(storyId).get();
      final story = await _storyFromDoc(doc, currentUid: uid);
      if (story == null || !story.hasSegments) {
        return (await fetchUpdates()).stories;
      }

      final normalizedSeenSegments =
          seenSegments.clamp(0, story.totalSegments).toInt();
      if (normalizedSeenSegments <= story.clampedSeenSegments) {
        return (await fetchUpdates()).stories;
      }

      // Written to the viewer's own per-viewer doc -- including when the
      // viewer is the owner checking their own story ring state.
      await _storiesRef.doc(storyId).collection('views').doc(uid).set(
        {
          'seenSegments': normalizedSeenSegments,
          'viewedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'We could not update that story right now.',
      );
    }

    return (await fetchUpdates()).stories;
  }

  @override
  Future<List<StatusStory>> deleteStatusSegment({
    required String storyId,
    required String segmentId,
  }) async {
    final uid = _requireCurrentUid;
    if (storyId != uid) {
      throw const UpdatesRepositoryException(
        'Only your own statuses can be deleted right now.',
      );
    }

    try {
      final doc = await _storiesRef.doc(uid).get();
      final story = await _storyFromDoc(doc, currentUid: uid);
      if (story == null) {
        throw const UpdatesRepositoryException(
          'That status item could not be found anymore.',
        );
      }

      final currentSegments = _segmentsFor(story);
      final segmentToDelete = currentSegments
          .cast<StatusStorySegment?>()
          .firstWhere((entry) => entry?.id == segmentId, orElse: () => null);
      if (segmentToDelete == null) {
        throw const UpdatesRepositoryException(
          'That status item could not be found anymore.',
        );
      }

      final remainingSegments = List<StatusStorySegment>.unmodifiable(
        currentSegments.where((segment) => segment.id != segmentId),
      );
      final nextStory = _storyAfterSegmentRemoval(story, remainingSegments);

      await _deleteOrphanedMedia(
        removedSegments: <StatusStorySegment>[segmentToDelete],
        remainingSegments: remainingSegments,
      );

      // That was the last item -- the next post starts a fresh story
      // cycle, so stale views of this now-gone content shouldn't count
      // toward it (see the matching comment in createStatus).
      if (remainingSegments.isEmpty) {
        await _clearViews(_storiesRef.doc(uid));
      }

      await _storiesRef.doc(uid).set(nextStory.toJson());
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'Could not delete that status item.',
      );
    }

    return (await fetchUpdates()).stories;
  }

  @override
  Future<List<StatusStory>> clearStory({required String storyId}) async {
    final uid = _requireCurrentUid;
    if (storyId != uid) {
      throw const UpdatesRepositoryException(
        'Only your own statuses can be cleared right now.',
      );
    }

    try {
      final doc = await _storiesRef.doc(uid).get();
      final story = await _storyFromDoc(doc, currentUid: uid);
      if (story == null) {
        throw const UpdatesRepositoryException(
          'That status item could not be found anymore.',
        );
      }

      final currentSegments = _segmentsFor(story);
      await _deleteOrphanedMedia(
        removedSegments: currentSegments,
        remainingSegments: const <StatusStorySegment>[],
      );

      // Clearing always empties the story -- the next post starts fresh,
      // so stale views of this now-gone content shouldn't count toward it
      // (see the matching comment in createStatus).
      await _clearViews(_storiesRef.doc(uid));

      final nextStory =
          _storyAfterSegmentRemoval(story, const <StatusStorySegment>[]);
      await _storiesRef.doc(uid).set(nextStory.toJson());
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'Could not clear your status.',
      );
    }

    return (await fetchUpdates()).stories;
  }

  @override
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) async {
    final uid = _requireCurrentUid;
    if (storyId != uid) {
      // Only the owner may list the views subcollection at all (see
      // firestore.rules) -- mirrors the interface's documented contract of
      // an empty list for anyone else's story.
      return const <StoryViewer>[];
    }

    try {
      final snapshot = await _storiesRef
          .doc(storyId)
          .collection('views')
          .orderBy('viewedAt', descending: true)
          .get();
      return _viewersFromSnapshot(snapshot, ownerUid: storyId);
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'Could not load viewers right now.',
      );
    }
  }

  @override
  Stream<List<StoryViewer>>? watchStoryViewers(String storyId) {
    final uid = _requireCurrentUid;
    if (storyId != uid) {
      return null;
    }

    return _storiesRef
        .doc(storyId)
        .collection('views')
        .orderBy('viewedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) => _viewersFromSnapshot(snapshot, ownerUid: storyId));
  }

  Future<List<StoryViewer>> _viewersFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required String ownerUid,
  }) async {
    final lookup = UserProfileLookup(firestore: _firestore);
    final viewers = await Future.wait(
      snapshot.docs
          .where((doc) => doc.id != ownerUid)
          .map((doc) async {
        final data = doc.data();
        final profile = await lookup.fetch(doc.id);
        final viewedAt = data['viewedAt'];
        return StoryViewer(
          uid: doc.id,
          name: profile?.name ?? 'WhatsWave user',
          avatarLabel: profile?.avatarLabel ?? '?',
          accentColor:
              Color(profile?.accentColorArgb ?? AppPalette.slate.toARGB32()),
          avatarUrl: profile?.avatarUrl,
          viewedAt: viewedAt is Timestamp ? viewedAt.toDate() : null,
          likedSegmentIds: _likedSegmentIdsFromViewData(data),
          seenSegments: (data['seenSegments'] as num?)?.toInt() ?? 0,
        );
      }),
    );

    return viewers;
  }

  List<String> _likedSegmentIdsFromViewData(Map<String, dynamic> data) {
    final raw = data['likedSegmentIds'];
    if (raw is List) {
      return raw.map((entry) => entry.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  @override
  Future<bool> isStoryLikedByMe(
    String storyId, {
    required String segmentId,
  }) async {
    final uid = _requireCurrentUid;
    if (storyId == uid) {
      return false;
    }

    try {
      final doc =
          await _storiesRef.doc(storyId).collection('views').doc(uid).get();
      final data = doc.data();
      if (data == null) {
        return false;
      }
      return _likedSegmentIdsFromViewData(data).contains(segmentId);
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'We could not load that reaction right now.',
      );
    }
  }

  @override
  Future<void> setStoryLiked(
    String storyId, {
    required String segmentId,
    required bool liked,
  }) async {
    final uid = _requireCurrentUid;
    if (storyId == uid) {
      return;
    }

    try {
      // Written to the viewer's own per-viewer doc, the same as
      // markStoryViewed above -- security rules only let that viewer write
      // it (see firestore.rules).
      await _storiesRef.doc(storyId).collection('views').doc(uid).set(
        liked
            ? {
                'likedSegmentIds': FieldValue.arrayUnion([segmentId]),
                'likedAt': FieldValue.serverTimestamp(),
                'liked': FieldValue.delete(),
              }
            : {
                'likedSegmentIds': FieldValue.arrayRemove([segmentId]),
                'liked': FieldValue.delete(),
              },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      throw UpdatesRepositoryException(
        e.message ?? 'We could not update that reaction right now.',
      );
    }
  }

  StatusStory _freshMyStatus(String uid) {
    final displayName = _firebaseAuth.currentUser?.displayName?.trim();
    final name = (displayName?.isEmpty ?? true) ? 'My Status' : displayName!;
    return StatusStory(
      id: uid,
      name: name,
      avatarLabel: _avatarLabelForName(name),
      previewText: '',
      timeLabel: 'Add now',
      accentColor: AppPalette.emerald,
      isMine: true,
      totalSegments: 0,
      seenSegments: 0,
    );
  }

  // The story doc's own name/avatarLabel/accentColor are a snapshot from
  // whenever it was last written -- the doc id IS the owner's uid, so this
  // can look their current identity up directly and prefer it, same as
  // every other feature that shows someone else's identity.
  Future<StatusStory?> _storyFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) async {
    if (!doc.exists) {
      return null;
    }
    final story = StatusStory.fromJson(doc.data());
    if (story == null) {
      return null;
    }
    final isMine = doc.id == currentUid;

    // WhatsApp-style 24h status lifetime. A segment with no postedAt is
    // legacy data written before this existed -- keep it rather than
    // guess whether it's expired.
    final liveSegments = story.segments.where((segment) {
      final postedAt = segment.postedAt;
      if (postedAt == null) {
        return true;
      }
      return DateTime.now().difference(postedAt) < const Duration(hours: 24);
    }).toList(growable: false);

    // Per-viewer seen-progress lives in each viewer's own views doc --
    // including the owner viewing their own story ring on "My Status".
    var seenSegments = story.seenSegments;
    if (liveSegments.isNotEmpty) {
      final viewDoc =
          await doc.reference.collection('views').doc(currentUid).get();
      seenSegments = (viewDoc.data()?['seenSegments'] as num?)?.toInt() ?? 0;
    }

    // Views are tracked per status item via each viewer's seenSegments --
    // only count someone toward the latest segment once they've actually
    // watched through to it (WhatsApp-style), not just because they viewed
    // an earlier item in the same story ring.
    var viewerCount = 0;
    if (isMine && liveSegments.isNotEmpty) {
      final viewsSnapshot = await doc.reference.collection('views').get();
      final requiredSeen = liveSegments.length;
      viewerCount = viewsSnapshot.docs.where((viewDoc) {
        if (viewDoc.id == doc.id) {
          return false;
        }
        final seen = (viewDoc.data()['seenSegments'] as num?)?.toInt() ?? 0;
        return seen >= requiredSeen;
      }).length;
    }

    final freshStory = story.copyWith(
      segments: liveSegments,
      totalSegments: liveSegments.length,
      seenSegments: liveSegments.isEmpty
          ? 0
          : seenSegments.clamp(0, liveSegments.length).toInt(),
      viewerCount: viewerCount,
    );

    final profile =
        await UserProfileLookup(firestore: _firestore).fetch(doc.id);
    return freshStory.copyWith(
      id: doc.id,
      isMine: isMine,
      name: profile?.name,
      avatarLabel: profile?.avatarLabel,
      accentColor: profile?.accentColorArgb == null
          ? null
          : Color(profile!.accentColorArgb!),
      avatarUrl: profile?.avatarUrl,
    );
  }

  Future<String?> _maybeImportMedia({
    required StatusStoryType type,
    String? localMediaPath,
  }) async {
    if (type == StatusStoryType.text) {
      return null;
    }
    return _mediaStore.importMedia(localMediaPath ?? '', type: type);
  }

  List<StatusStorySegment> _segmentsFor(StatusStory story) {
    if (story.segments.isNotEmpty) {
      return story.segments;
    }
    if (!story.hasSegments) {
      return const <StatusStorySegment>[];
    }
    return <StatusStorySegment>[
      StatusStorySegment(
        id: '${story.id}-legacy',
        type: story.type,
        previewText: story.previewText,
      ),
    ];
  }

  /// Deletes every doc in [storyRef]'s `views` subcollection -- called
  /// whenever a story's content is fully gone (either every segment aged
  /// out past 24h, or the owner explicitly deleted/cleared it), so the
  /// next thing posted starts with a clean viewer count instead of
  /// inheriting views recorded against content that no longer exists.
  Future<void> _clearViews(
      DocumentReference<Map<String, dynamic>> storyRef) async {
    final viewsSnapshot = await storyRef.collection('views').get();
    if (viewsSnapshot.docs.isEmpty) {
      return;
    }
    final batch = _firestore.batch();
    for (final doc in viewsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  StatusStory _storyAfterSegmentRemoval(
    StatusStory story,
    List<StatusStorySegment> remainingSegments,
  ) {
    if (remainingSegments.isEmpty) {
      return story.copyWith(
        type: StatusStoryType.text,
        previewText: 'Tap to add a text, photo, or video update',
        timeLabel: 'Add now',
        totalSegments: 0,
        seenSegments: 0,
        segments: const <StatusStorySegment>[],
      );
    }

    final latestSegment = remainingSegments.last;
    return story.copyWith(
      type: latestSegment.type,
      previewText: latestSegment.previewText,
      timeLabel: 'Just now',
      totalSegments: remainingSegments.length,
      seenSegments: 0,
      segments: remainingSegments,
      postedAt: latestSegment.postedAt,
    );
  }

  Future<void> _deleteOrphanedMedia({
    required List<StatusStorySegment> removedSegments,
    required List<StatusStorySegment> remainingSegments,
  }) async {
    final remainingPaths = remainingSegments
        .map((segment) => segment.localMediaPath?.trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();
    final orphanedPaths = removedSegments
        .map((segment) => segment.localMediaPath?.trim() ?? '')
        .where((path) => path.isNotEmpty && !remainingPaths.contains(path))
        .toSet();
    if (orphanedPaths.isEmpty) {
      return;
    }
    await _mediaStore.deleteMedia(orphanedPaths);
  }

  List<StatusMediaOverlayItem> _legacyOverlayItems({
    required String caption,
    required StatusTextStyle? textStyle,
    required String? emoji,
    required List<String> stickers,
    required StatusMusicTrack? musicTrack,
  }) {
    final items = <StatusMediaOverlayItem>[];
    if (caption.isNotEmpty) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-caption',
          type: StatusMediaOverlayType.text,
          label: caption,
          positionDx: 0.5,
          positionDy: 0.82,
          scale: 1,
          textStyle: textStyle,
        ),
      );
    }
    if (emoji?.isNotEmpty == true) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-emoji',
          type: StatusMediaOverlayType.emoji,
          label: emoji!,
          positionDx: 0.8,
          positionDy: 0.18,
          scale: 1,
        ),
      );
    }
    for (var index = 0; index < stickers.length; index++) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-sticker-$index',
          type: StatusMediaOverlayType.sticker,
          label: stickers[index],
          positionDx: 0.32 + (0.18 * (index % 3)),
          positionDy: 0.62 + (0.1 * (index ~/ 3)),
          scale: 1,
        ),
      );
    }
    if (musicTrack != null) {
      items.add(
        StatusMediaOverlayItem(
          id: 'overlay-music',
          type: StatusMediaOverlayType.music,
          label: musicTrack.title,
          subtitle: musicTrack.artist,
          positionDx: 0.24,
          positionDy: 0.14,
          scale: 1,
          accentColorValue: musicTrack.colorValue,
        ),
      );
    }
    return List<StatusMediaOverlayItem>.unmodifiable(items);
  }

  String _avatarLabelForName(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'WW';
    }
    if (parts.length == 1) {
      final clean = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return clean.isEmpty
          ? 'WW'
          : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
