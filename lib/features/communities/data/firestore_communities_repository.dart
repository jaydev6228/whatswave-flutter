import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

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
class FirestoreCommunitiesRepository implements CommunitiesRepository {
  FirestoreCommunitiesRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
    DeviceContactsService? deviceContactsService,
    List<CommunityContact>? initialContacts,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _deviceContactsService =
            deviceContactsService ?? const NativeDeviceContactsService(),
        _contacts = initialContacts == null
            ? const <CommunityContact>[]
            : List<CommunityContact>.unmodifiable(initialContacts),
        _hasLoadedContacts = initialContacts != null;

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  final DeviceContactsService _deviceContactsService;
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
      final snapshot = await _communitiesRef
          .where('memberUids', arrayContains: uid)
          .get();
      final communities = snapshot.docs
          .map(_communityFromDoc)
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
          final doc = await _firestore.collection('phoneDirectory').doc(key).get();
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
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not update that community.',
      );
    }
    return fetchOverview();
  }

  @override
  Future<CommunitiesOverview> deleteCommunity(String communityId) async {
    _requireCurrentUid;
    try {
      await _communitiesRef.doc(communityId).delete();
    } on FirebaseException catch (e) {
      throw CommunitiesRepositoryException(
        e.message ?? 'Could not delete that community.',
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
  ) {
    final data = doc.data();
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

    final memberUids = (data['memberUids'] as List<dynamic>?)?.cast<String>();

    return CommunityHub(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      avatarLabel: (data['avatarLabel'] as String?) ?? '',
      accentColor: Color((data['accentColorArgb'] as int?) ?? 0xFF000000),
      memberCount: memberUids != null && memberUids.isNotEmpty
          ? memberUids.length
          : (data['memberCount'] as int?) ?? 1,
      announcement: announcement,
      groups: groups,
      unreadCount: (data['unreadCount'] as int?) ?? 0,
      invitedContactIds: List<String>.unmodifiable(
        (data['invitedContactIds'] as List<dynamic>?)?.cast<String>() ??
            const <String>[],
      ),
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
    );
  }

  Map<String, Object?> _communityToJson(CommunityHub community) {
    return {
      'title': community.title,
      'description': community.description,
      'avatarLabel': community.avatarLabel,
      'accentColorArgb': community.accentColor.toARGB32(),
      'memberCount': community.memberCount,
      'unreadCount': community.unreadCount,
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
