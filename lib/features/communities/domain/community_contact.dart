import 'package:flutter/material.dart';

enum CommunityMembershipState { none, invited, member }

extension CommunityMembershipStateX on CommunityMembershipState {
  String get label => switch (this) {
        CommunityMembershipState.none => 'Invite',
        CommunityMembershipState.invited => 'Invited',
        CommunityMembershipState.member => 'Member',
      };
}

class CommunityContact {
  const CommunityContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.avatarLabel,
    required this.accentColor,
    required this.about,
    this.isOnWhatsWave = true,
    this.appInviteSent = false,
    this.memberCommunityIds = const <String>[],
    this.pendingCommunityInviteIds = const <String>[],
    this.matchedUid,
    this.username,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final String avatarLabel;
  final Color accentColor;
  final String about;

  /// Optional WhatsWave handle (without "@") for search, when published on
  /// the matched user's `userProfiles` document.
  final String? username;
  final bool isOnWhatsWave;
  final bool appInviteSent;
  final List<String> memberCommunityIds;
  final List<String> pendingCommunityInviteIds;

  /// This contact's real Firebase uid, if [isOnWhatsWave] and matched via
  /// the phoneDirectory lookup -- null for local/demo contacts. Lets
  /// features like Calls place a real call to a real registered user.
  final String? matchedUid;

  CommunityMembershipState membershipStateFor(String communityId) {
    if (memberCommunityIds.contains(communityId)) {
      return CommunityMembershipState.member;
    }
    if (pendingCommunityInviteIds.contains(communityId)) {
      return CommunityMembershipState.invited;
    }
    return CommunityMembershipState.none;
  }

  CommunityContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? avatarLabel,
    Color? accentColor,
    String? about,
    bool? isOnWhatsWave,
    bool? appInviteSent,
    List<String>? memberCommunityIds,
    List<String>? pendingCommunityInviteIds,
    String? matchedUid,
    String? username,
  }) {
    return CommunityContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      accentColor: accentColor ?? this.accentColor,
      about: about ?? this.about,
      username: username ?? this.username,
      isOnWhatsWave: isOnWhatsWave ?? this.isOnWhatsWave,
      appInviteSent: appInviteSent ?? this.appInviteSent,
      memberCommunityIds: memberCommunityIds ?? this.memberCommunityIds,
      pendingCommunityInviteIds:
          pendingCommunityInviteIds ?? this.pendingCommunityInviteIds,
      matchedUid: matchedUid ?? this.matchedUid,
    );
  }
}
