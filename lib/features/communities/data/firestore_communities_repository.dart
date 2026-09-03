import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../core/media/media_uploader.dart';
import '../../../core/sample/demo_data.dart';
import '../../../core/utils/phone_number_matching.dart';
import '../../../core/utils/user_profile_lookup.dart';
import '../domain/community_announcement.dart';
import '../domain/community_contact.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';
import 'communities_overview.dart';
import 'communities_repository.dart';
import 'device_contacts_service.dart';

/// Firestore-backed [CommunitiesRepository].
///
/// Communities are real Firestore documents (see the class doc below for
/// the write-authorization simplification). Contacts are real device
/// contacts (via [DeviceContactsService]), enriched with "on WhatsWave"
/// status by checking each contact's [phoneMatchKey] against a
/// `phoneDirectory` collection that [FirebaseAuthRepository] populates on
/// profile save. This is a best-effort, approximate match (see
/// `phone_number_matching.dart`), and does an individual Firestore read per
/// contact -- fine at demo/personal-address-book scale, not something that
/// would scale to thousands of contacts without a batched/indexed approach.
///
/// Device contacts are fetched once per repository instance (on first
/// access) and cached in [_contacts] from then on, exactly like
/// [FakeCommunitiesRepository]'s in-memory list -- this preserves session
/// mutations (shareAppInvite, invite bookkeeping) across repeated
/// `fetchOverview()` calls instead of re-reading the address book (and
/// losing that state) every time.
///
/// Communities are membership-gated: a `memberUids` array on the document
/// (seeded with just the creator at `createCommunity`) is what
/// `firestore.rules` checks for read access -- only members can see a
/// community at all, matching a real private group. Only the owner
/// (`ownerUid`) can write the document, including adding members, so
/// joining today only happens via the owner inviting a contact (see
/// `inviteContactToCommunity`) -- there's no self-service join/invite-link
/// flow yet, and no separate pending-invite/accept step: being invited by
/// the owner immediately grants membership.
///
/// Roles live in an `adminUids` array seeded with the creator. That list,
/// not `ownerUid`, is what every admin gate reads -- WhatsApp communities
/// have real admin roles, capped at 20 ("You can assign up to 20 community
/// admin roles.",
/// https://www.whatsapp.com/communities/learning/settingupyourcommunity) --
/// and an admin may write `adminUids` and nothing else. `ownerUid` still
/// names the creator, who can never be demoted and is the only one who may
/// deactivate.
///
/// The one write a plain member may make is removing their own uid from
/// `memberUids` and `adminUids` (see [exitCommunity]) -- WhatsApp
/// guarantees every member a way out of a community independently of its
/// admins (https://faq.whatsapp.com/1312647189536807), and without that
/// carve-out an owner-only write rule means being added is permanent.
class FirestoreCommunitiesRepository implements CommunitiesRepository {
  FirestoreCommunitiesRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
    DeviceContactsService? deviceContactsService,
    List<CommunityContact>? initialContacts,
    MediaUploader? mediaUploader,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _deviceContactsService =
            deviceContactsService ?? const NativeDeviceContactsService(),
        _mediaUploader = mediaUploader ?? FirebaseMediaUploader(),
        _contacts = initialContacts == null
            ? const <CommunityContact>[]
            : List<CommunityContact>.unmodifiable(initialContacts),
        _hasLoadedContacts = initialContacts != null;

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final DeviceContactsService _deviceContactsService;
  final MediaUploader _mediaUploader;
  List<CommunityContact> _contacts;
  bool _hasLoadedContacts;

  CollectionReference<Map<String, dynamic>> get _communitiesRef =>
      _firestore.collection('communities');

  String get _requireCurrentUid {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid == null) {
      throw const CommunitiesRepositoryException(
        'Sign in again to load your communities.',
      );
    }
    return uid;
  }

  @override
  Future<CommunitiesOverview> fetchOverview() async {
    final uid = _requireCurrentUid;
    await _ensureContactsLoaded();
    try {
      final snapshot =
          await _communitiesRef.where('memberUids', arrayContains: uid).get();
      final communities = snapshot.docs
          .map((doc) => _communityFromDoc(doc, uid))
          .whereType<CommunityHub>()
          .toList(growable: false);
      return CommunitiesOverview(
        communities: communities,
        contacts: _cloneContacts(_contacts),
      );
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'We could not load your communities right now.',
      );
    }
  }

  /// Fetches real device contacts and enriches them with "on WhatsWave"
  /// status, once per repository instance. Degrades gracefully to an empty
  /// contact list on failure (e.g. permission not actually granted at the
  /// OS level) rather than blocking the whole Communities screen -- the app
  /// already gates the contacts UI behind its own permission flow before
  /// this is ever called in practice.
  Future<void> _ensureContactsLoaded() async {
    if (_hasLoadedContacts) {
      return;
    }
    _hasLoadedContacts = true;

    try {
      final deviceContacts = await _deviceContactsService.fetchDeviceContacts();
      _contacts = await _enrichWithWhatsWaveStatus(deviceContacts);
    } catch (_) {
      _contacts = const <CommunityContact>[];
    }
  }

  Future<List<CommunityContact>> _enrichWithWhatsWaveStatus(
    List<CommunityContact> contacts,
  ) async {
    final currentUid = _firebaseAuth.currentUser?.uid;
    final profileLookup = UserProfileLookup(firestore: _firestore);
    final enriched = await Future.wait(
      contacts.map((contact) async {
        final key = phoneMatchKey(contact.phoneNumber);
        if (key.isEmpty) {
          return contact;
        }
        try {
          final doc =
              await _firestore.collection('phoneDirectory').doc(key).get();
          final matchedUid = doc.data()?['uid'] as String?;
          if (matchedUid == null || matchedUid == currentUid) {
            return contact;
          }
          // Prefer the matched account's own current WhatsWave name/avatar
          // over whatever this device's address book has saved for them --
          // otherwise a contact who renames themselves in WhatsWave keeps
          // showing their old (or just their plain phone-book) name here
          // forever.
          final profile = await profileLookup.fetch(matchedUid);
          return contact.copyWith(
            isOnWhatsWave: true,
            matchedUid: matchedUid,
            name: profile?.name,
            avatarLabel: profile?.avatarLabel,
            accentColor: profile?.accentColorArgb == null
                ? null
                : Color(profile!.accentColorArgb!),
            username: profile?.username,
          );
        } on FirebaseException {
          return contact;
        }
      }),
    );
    return List<CommunityContact>.unmodifiable(enriched);
  }

  @override
  Future<CommunitiesOverview> createCommunity({
    required String title,
    required String description,
  }) async {
    final uid = _requireCurrentUid;
    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    if (normalizedTitle.isEmpty || normalizedDescription.isEmpty) {
      throw const CommunitiesRepositoryException(
        'Add a name and a short description before creating a community.',
      );
    }

    try {
      final docRef = _communitiesRef.doc();
      final draft = DemoData.buildDraftCommunity(
        id: docRef.id,
        title: normalizedTitle,
        description: normalizedDescription,
      );
      await docRef.set({
        ..._communityToJson(draft),
        'ownerUid': uid,
        'memberUids': [uid],
        // The creator starts as the only admin. Nothing else can seed this
        // list (firestore.rules pins it to exactly [creator] at create), so
        // every later admin is someone an admin promoted.
        'adminUids': [uid],
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'We could not create that community right now.',
      );
    }

    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> markCommunityOpened(String communityId) async {
    _requireCurrentUid;
    try {
      await _communitiesRef.doc(communityId).update({'unreadCount': 0});
    } on FirebaseException catch (e) {
      // `unreadCount` lives on the shared community document, which only the
      // owner may write, so a plain member opening a community always gets
      // permission-denied here. Opening is a read, not a mutation the member
      // asked for -- surfacing it would put an error banner on every single
      // community a member opens -- so this one code is swallowed while any
      // other failure still surfaces.
      if (e.code == 'permission-denied') {
        return fetchOverview();
      }
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update that community.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> deactivateCommunity(String communityId) async {
    final uid = _requireCurrentUid;
    try {
      // Deactivation stays with the creator alone, not every admin: it is
      // irreversible (https://faq.whatsapp.com/785738926054798) while an
      // admin role is a grant an owner hands out for adding and removing
      // members and groups
      // (https://www.whatsapp.com/communities/learning/settingupyourcommunity),
      // and a promotion must not double as a destroy button. `firestore.rules`
      // already enforces this, but checking first turns a raw
      // permission-denied into the reason, and stops a member believing
      // they removed a community that is still standing.
      final doc = await _communitiesRef.doc(communityId).get();
      final data = doc.data();
      if (data == null) {
        throw const CommunitiesRepositoryException(
          'That community is no longer available.',
        );
      }
      final owner = data['ownerUid'] as String?;
      if (owner != null && owner != uid) {
        throw const CommunitiesRepositoryException(
          'Only the person who created this community can deactivate it. '
          'You can exit it instead.',
        );
      }
      // Release the groups BEFORE the community goes, not after: if this
      // half fails the community is still standing and the action can be
      // retried, whereas the other order strands threads nothing can
      // reach.
      await _releaseGroupThreads(data);
      // A state change, not a delete. Deactivation must leave the member
      // groups intact (https://faq.whatsapp.com/785738926054798), and a
      // hard delete took the `groups` roster -- the only record of which
      // threads belonged here -- down with the document.
      // `deactivatedAt` is what `_communityFromDoc` filters on, so this
      // one write is what removes the community from every member's list.
      await _communitiesRef.doc(communityId).update({
        'deactivatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not deactivate that community.',
      );
    }
    return fetchOverview();
  }

  /// Turns every member group's backing thread back into an ordinary group
  /// chat, so it survives its community and shows up in Chats.
  ///
  /// WhatsApp's deactivation disconnects the member groups and they stay
  /// usable (https://faq.whatsapp.com/785738926054798). Here "disconnected"
  /// has to mean clearing `isCommunityGroup`: ChatsController hides
  /// community-backed threads from every Chats list view because the
  /// Communities tab owns them, so a thread still flagged after its
  /// community is gone belongs to nobody and is reachable from nowhere.
  ///
  /// The announcement thread is deliberately NOT released. WhatsApp closes
  /// the announcement group on deactivation, and leaving it flagged is
  /// exactly that: it stays out of Chats and its only entry point (this
  /// community) is gone, so nobody can post to it again -- without
  /// deleting anyone's announcement history, which `firestore.rules`
  /// forbids for chat threads anyway (`allow delete: if false`).
  ///
  /// Writes `chatThreads` from the communities side on purpose: it is one
  /// field, permitted by the existing any-participant thread update rule,
  /// and the alternative (teaching Chats to un-hide orphaned community
  /// threads) would spread the same decision across two features.
  Future<void> _releaseGroupThreads(Map<String, dynamic> data) async {
    final groups = (data['groups'] as List<dynamic>?) ?? const [];
    for (final group in groups.whereType<Map<String, dynamic>>()) {
      final threadId = group['threadId'] as String?;
      if (threadId == null) {
        continue;
      }
      await _firestore
          .collection('chatThreads')
          .doc(threadId)
          .update({'isCommunityGroup': false});
    }
  }

  @override
  Future<CommunitiesOverview> exitCommunity(String communityId) async {
    final uid = _requireCurrentUid;
    try {
      final owner = await _ownerUid(communityId);
      if (owner == uid) {
        // WhatsApp keeps a community's own admin out of the plain "exit"
        // path -- the admin-side action is deactivating it
        // (https://faq.whatsapp.com/785738926054798). Letting the owner
        // drop out of `memberUids` here would strand a community nobody
        // can read or delete any more, since read access is the roster.
        throw const CommunitiesRepositoryException(
          'You created this community. Delete it instead of exiting.',
        );
      }
      // Removing yourself from `memberUids` is the whole exit: that array is
      // both the read-access roster and the membership list, so this drops
      // the community out of your list while leaving it intact for everyone
      // else (https://faq.whatsapp.com/1312647189536807).
      // Both rosters, in one write: leaving while still listed in
      // `adminUids` would leave a ghost admin who cannot even read the
      // document, still occupying one of the 20 admin slots. The creator
      // never reaches here (turned back above) and is always an admin, so
      // this can never empty the admin roster.
      await _communitiesRef.doc(communityId).update({
        'memberUids': FieldValue.arrayRemove([uid]),
        'adminUids': FieldValue.arrayRemove([uid]),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not exit that community.',
      );
    }
    return fetchOverview();
  }

  Future<String?> _ownerUid(String communityId) async {
    final doc = await _communitiesRef.doc(communityId).get();
    return doc.data()?['ownerUid'] as String?;
  }

  @override
  Future<CommunitiesOverview> setCommunityAdmin({
    required String communityId,
    required String memberUid,
    required bool isAdmin,
  }) async {
    _requireCurrentUid;
    try {
      // No pre-read gate on the role itself: CommunitiesController already
      // refuses the admin-only, 20-cap, no-self-promotion and
      // no-owner-demotion cases with a readable reason, and
      // `firestore.rules` re-checks all four, so a stale client is refused
      // by the backend rather than trusted.
      //
      // The owner is unioned in alongside the promotion because the rules
      // require ownerUid to stay in adminUids -- on a community created
      // before this list existed it isn't in there yet, and a bare
      // arrayUnion would write a roster without them and be refused.
      final owner = isAdmin ? await _ownerUid(communityId) : null;
      await _communitiesRef.doc(communityId).update({
        'adminUids': isAdmin
            ? FieldValue.arrayUnion([memberUid, if (owner != null) owner])
            : FieldValue.arrayRemove([memberUid]),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not change that admin role.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> renameCommunity({
    required String communityId,
    required String title,
  }) async {
    _requireCurrentUid;
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const CommunitiesRepositoryException(
        'Enter a community name.',
      );
    }
    try {
      await _communitiesRef.doc(communityId).update({
        'title': trimmed,
        'avatarLabel': CommunityHub.avatarLabelForTitle(trimmed),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not rename that community.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> updateCommunityDescription({
    required String communityId,
    required String description,
  }) async {
    _requireCurrentUid;
    try {
      await _communitiesRef.doc(communityId).update({
        'description': description.trim(),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update that community.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> updateCommunityAvatar({
    required String communityId,
    required File photo,
  }) async {
    _requireCurrentUid;
    if (!await photo.exists()) {
      throw const CommunitiesRepositoryException(
        'That photo is no longer available.',
      );
    }

    final extension = photo.path.contains('.')
        ? photo.path.substring(photo.path.lastIndexOf('.'))
        : '.jpg';
    try {
      final downloadUrl = await _mediaUploader.uploadFile(
        photo,
        storagePath: 'communityPhotos/$communityId/icon$extension',
      );
      await _communitiesRef.doc(communityId).update({
        'avatarUrl': downloadUrl,
      });
    } on MediaUploadException catch (e) {
      throw CommunitiesRepositoryException(e.message);
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update that community photo right now.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> deleteCommunityAvatar(String communityId) async {
    _requireCurrentUid;
    try {
      await _communitiesRef.doc(communityId).update({
        'avatarUrl': FieldValue.delete(),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not remove that community photo.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> attachGroupThread({
    required String communityId,
    required String groupId,
    required String threadId,
  }) async {
    _requireCurrentUid;
    try {
      final doc = await _communitiesRef.doc(communityId).get();
      final data = doc.data();
      if (data == null) {
        throw const CommunitiesRepositoryException(
          'That community is no longer available.',
        );
      }
      final groupsRaw = (data['groups'] as List<dynamic>?) ?? const [];
      final updatedGroups = groupsRaw.whereType<Map<String, dynamic>>().map(
        (map) {
          if (map['id'] != groupId) {
            return map;
          }
          return {...map, 'threadId': threadId};
        },
      ).toList(growable: false);
      await _communitiesRef.doc(communityId).update({'groups': updatedGroups});
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update that group.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> attachAnnouncementThread({
    required String communityId,
    required String threadId,
  }) async {
    _requireCurrentUid;
    try {
      await _communitiesRef.doc(communityId).update({
        'announcementThreadId': threadId,
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update announcements.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  }) async {
    _requireCurrentUid;
    await _ensureContactsLoaded();
    final contact = _contactById(contactId);
    if (!contact.isOnWhatsWave || contact.matchedUid == null) {
      throw const CommunitiesRepositoryException(
        'That person needs an app invite before they can join a community.',
      );
    }

    final membershipState = contact.membershipStateFor(communityId);
    if (membershipState == CommunityMembershipState.member ||
        membershipState == CommunityMembershipState.invited) {
      return fetchOverview();
    }

    try {
      final doc = await _communitiesRef.doc(communityId).get();
      if (!doc.exists) {
        throw const CommunitiesRepositoryException(
          'That community is no longer available. Pull to refresh and try again.',
        );
      }

      // "Inviting" grants membership immediately -- only the owner can
      // write this document at all (see the class doc comment), so there's
      // no separate pending/accept step yet.
      await _communitiesRef.doc(communityId).update({
        'invitedContactIds': FieldValue.arrayUnion([contactId]),
        'memberUids': FieldValue.arrayUnion([contact.matchedUid]),
      });
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'We could not send that community invite right now.',
      );
    }

    _contacts = List<CommunityContact>.unmodifiable(
      _contacts.map((entry) {
        if (entry.id != contactId) {
          return entry;
        }
        return entry.copyWith(
          memberCommunityIds: List<String>.unmodifiable([
            ...entry.memberCommunityIds,
            communityId,
          ]),
        );
      }),
    );

    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> shareAppInvite(String contactId) async {
    _requireCurrentUid;
    await _ensureContactsLoaded();
    final contact = _contactById(contactId);
    if (contact.isOnWhatsWave) {
      return fetchOverview();
    }

    _contacts = List<CommunityContact>.unmodifiable(
      _contacts.map((entry) {
        if (entry.id != contactId) {
          return entry;
        }
        return entry.copyWith(appInviteSent: true);
      }),
    );

    return fetchOverview();
  }

  @override
  Stream<void>? watchDeviceContactsChanged() =>
      _deviceContactsService.watchContactsChanged();

  CommunityContact _contactById(String contactId) {
    for (final contact in _contacts) {
      if (contact.id == contactId) {
        return contact;
      }
    }
    throw const CommunitiesRepositoryException(
      'That contact is no longer available. Pull to refresh and try again.',
    );
  }

  CommunityHub? _communityFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String currentUid,
  ) {
    final data = doc.data();
    // A deactivated community is gone for everyone, not just for the admin
    // who deactivated it, and deactivation cannot be undone
    // (https://faq.whatsapp.com/785738926054798). The document deliberately
    // survives now (a delete took the group roster with it), so the list is
    // filtered here rather than relying on the document being gone.
    // Filtered client-side rather than in the query because pairing an
    // equality filter with the `memberUids` array-contains would need a
    // composite index for a handful of documents per user.
    if (data['deactivatedAt'] != null) {
      return null;
    }
    final announcementRaw = data['announcement'];
    if (announcementRaw is! Map<String, dynamic>) {
      return null;
    }

    final publishedAt = announcementRaw['publishedAt'];
    final announcement = CommunityAnnouncement(
      headline: (announcementRaw['headline'] as String?) ?? '',
      body: (announcementRaw['body'] as String?) ?? '',
      publishedAt:
          publishedAt is Timestamp ? publishedAt.toDate() : DateTime.now(),
    );

    final groupsRaw = (data['groups'] as List<dynamic>?) ?? const [];
    final groups = groupsRaw
        .whereType<Map<String, dynamic>>()
        .map(_groupFromMap)
        .toList(growable: false);

    final memberUids =
        (data['memberUids'] as List<dynamic>?)?.cast<String>() ??
            const <String>[];
    final adminUids = (data['adminUids'] as List<dynamic>?)?.cast<String>() ??
        const <String>[];
    final ownerUid = data['ownerUid'] as String?;

    return CommunityHub(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      avatarLabel: (data['avatarLabel'] as String?) ?? '',
      accentColor: Color((data['accentColorArgb'] as int?) ?? 0xFF000000),
      // `memberUids` is the read-access roster and is always seeded with the
      // creator, so its raw length read one higher than every membership view
      // in the app -- "3 members" over a two-person "Already added" list.
      // Count the people who were actually added, and derive it from the
      // roster rather than the stored `memberCount`, which was written once at
      // create time and never recomputed as members joined.
      memberCount:
          memberUids.where((memberUid) => memberUid != currentUid).length,
      announcement: announcement,
      groups: groups,
      unreadCount: (data['unreadCount'] as int?) ?? 0,
      invitedContactIds: List<String>.unmodifiable(
        (data['invitedContactIds'] as List<dynamic>?)?.cast<String>() ??
            const <String>[],
      ),
      announcementThreadId: data['announcementThreadId'] as String?,
      // Admin is roster membership now, not "created it". Documents written
      // before `adminUids` existed have none, so they fall back to the
      // owner -- otherwise every pre-existing community would come back
      // with no admin at all and nobody able to promote one.
      viewerIsAdmin: adminUids.isEmpty
          ? ownerUid == currentUid
          : adminUids.contains(currentUid),
      memberUids: List<String>.unmodifiable(memberUids),
      adminUids: List<String>.unmodifiable(
        adminUids.isEmpty && ownerUid != null ? <String>[ownerUid] : adminUids,
      ),
      ownerUid: ownerUid,
      viewerUid: currentUid,
      avatarUrl: data['avatarUrl'] as String?,
    );
  }

  CommunityGroupPreview _groupFromMap(Map<String, dynamic> map) {
    final lastActivityAt = map['lastActivityAt'];
    return CommunityGroupPreview(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      summary: (map['summary'] as String?) ?? '',
      memberCount: (map['memberCount'] as int?) ?? 0,
      lastActivityAt: lastActivityAt is Timestamp
          ? lastActivityAt.toDate()
          : DateTime.now(),
      unreadCount: (map['unreadCount'] as int?) ?? 0,
      threadId: map['threadId'] as String?,
    );
  }

  Map<String, Object?> _communityToJson(CommunityHub community) {
    return {
      'title': community.title,
      'description': community.description,
      'avatarLabel': community.avatarLabel,
      if (community.avatarUrl != null) 'avatarUrl': community.avatarUrl,
      'accentColorArgb': community.accentColor.toARGB32(),
      // No 'memberCount' -- a denormalized copy written only at create time
      // goes stale the moment someone is added, and nothing reads it now that
      // the count is derived from `memberUids` on read.
      'unreadCount': community.unreadCount,
      if (community.announcementThreadId != null)
        'announcementThreadId': community.announcementThreadId,
      'announcement': {
        'headline': community.announcement.headline,
        'body': community.announcement.body,
        'publishedAt': Timestamp.fromDate(community.announcement.publishedAt),
      },
      'groups': community.groups
          .map((group) => {
                'id': group.id,
                'name': group.name,
                'summary': group.summary,
                'memberCount': group.memberCount,
                'lastActivityAt': Timestamp.fromDate(group.lastActivityAt),
                'unreadCount': group.unreadCount,
                if (group.threadId != null) 'threadId': group.threadId,
              })
          .toList(growable: false),
      'invitedContactIds': community.invitedContactIds,
    };
  }

  List<CommunityContact> _cloneContacts(List<CommunityContact> contacts) {
    return List<CommunityContact>.unmodifiable(
      contacts.map((contact) {
        return contact.copyWith(
          memberCommunityIds:
              List<String>.unmodifiable(contact.memberCommunityIds),
          pendingCommunityInviteIds:
              List<String>.unmodifiable(contact.pendingCommunityInviteIds),
        );
      }),
    );
  }
}
