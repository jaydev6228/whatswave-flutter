import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

import '../../../core/sample/demo_data.dart';
import '../domain/community_announcement.dart';
import '../domain/community_contact.dart';
import '../domain/community_group_preview.dart';
import '../domain/community_hub.dart';
import 'communities_overview.dart';
import 'communities_repository.dart';

/// Firestore-backed [CommunitiesRepository] -- communities only.
///
/// Deliberate scope decision: contacts stay an in-memory fake list seeded
/// from [DemoData.buildCommunityContacts], exactly like
/// [FakeCommunitiesRepository]. "Contacts" represents the device's address
/// book, which is a fundamentally different (and unimplemented) concern --
/// real device contacts integration would be a separate feature, not part
/// of moving *community* data to a real backend. Contact mutations
/// (shareAppInvite, invite bookkeeping) are session-only and never
/// persisted anywhere.
///
/// Known simplification, same pattern as the auth/chats/updates slices:
/// only the community's creator (`ownerUid`) can write it. Any signed-in
/// user can read any community (like a real community directory). Since
/// there's only ever one real test account today, every community that
/// exists was created by -- and is therefore writable by -- the current
/// user; this would need real membership-based write rules for genuine
/// multi-user communities.
class FirestoreCommunitiesRepository implements CommunitiesRepository {
  FirestoreCommunitiesRepository({
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
    List<CommunityContact>? initialContacts,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance,
        _contacts = List<CommunityContact>.unmodifiable(
          initialContacts ?? DemoData.buildCommunityContacts(),
        );

  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;
  List<CommunityContact> _contacts;

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
    _requireCurrentUid;
    try {
      final snapshot = await _communitiesRef.get();
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
      await docRef.set({..._communityToJson(draft), 'ownerUid': uid});
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
  Future<CommunitiesOverview> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  }) async {
    _requireCurrentUid;
    final contact = _contactById(contactId);
    if (!contact.isOnWhatsWave) {
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

      await _communitiesRef.doc(communityId).update({
        'invitedContactIds': FieldValue.arrayUnion([contactId]),
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
          pendingCommunityInviteIds: List<String>.unmodifiable([
            ...entry.pendingCommunityInviteIds,
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

    return CommunityHub(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      description: (data['description'] as String?) ?? '',
      avatarLabel: (data['avatarLabel'] as String?) ?? '',
      accentColor: Color((data['accentColorArgb'] as int?) ?? 0xFF000000),
      memberCount: (data['memberCount'] as int?) ?? 1,
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
