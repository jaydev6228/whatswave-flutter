import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/permissions/app_permission_service.dart';
import '../data/communities_overview.dart';
import '../data/communities_repository.dart';
import '../domain/community_contact.dart';
import '../domain/community_hub.dart';
import '../domain/community_thread_context.dart';
import '../domain/contact_access_status.dart';

enum ContactListFilter { all, onWhatsWave, invite }

/// Creates a real group [ChatThread] for community messaging and returns
/// its id, or null on failure -- matches ChatsController.createGroup's
/// signature so it can be passed straight through at the composition root.
typedef GroupThreadCreator = Future<String?> Function({
  required String name,
  required List<String> memberUids,
  bool isCommunityGroup,
  bool isAnnouncementOnly,
});

class CommunitiesController extends ChangeNotifier {
  CommunitiesController({
    required CommunitiesRepository repository,
    AppPermissionService? permissionService,
    GroupThreadCreator? createGroupThread,
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService(),
        _createGroupThread = createGroupThread;

  final CommunitiesRepository _repository;
  final AppPermissionService _permissionService;

  /// Optional -- absent in contexts (e.g. most tests) that don't need real
  /// group messaging wired up. When set, a community's first group gets a
  /// real backing thread as soon as it has at least one on-WhatsWave
  /// member (see _ensureGroupThreadIfPossible).
  final GroupThreadCreator? _createGroupThread;

  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isCreatingCommunity = false;
  bool _isRequestingContactsAccess = false;
  String? _errorMessage;
  String _searchQuery = '';
  ContactListFilter _contactFilter = ContactListFilter.all;
  ContactAccessStatus _contactAccessStatus = ContactAccessStatus.unknown;
  List<CommunityHub> _communities = const <CommunityHub>[];
  List<CommunityContact> _contacts = const <CommunityContact>[];
  final Set<String> _busyCommunityIds = <String>{};
  final Set<String> _busyContactIds = <String>{};
  StreamSubscription<void>? _deviceContactsChangedSubscription;

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isCreatingCommunity => _isCreatingCommunity;
  bool get isRequestingContactsAccess => _isRequestingContactsAccess;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  ContactListFilter get contactFilter => _contactFilter;
  ContactAccessStatus get contactAccessStatus => _contactAccessStatus;
  List<CommunityHub> get communities =>
      List<CommunityHub>.unmodifiable(_communities);
  List<CommunityContact> get contacts =>
      List<CommunityContact>.unmodifiable(_contacts);

  List<CommunityHub> get visibleCommunities {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return _communities.where((community) {
      if (normalizedQuery.isEmpty) {
        return true;
      }

      return community.title.toLowerCase().contains(normalizedQuery) ||
          community.description.toLowerCase().contains(normalizedQuery) ||
          community.announcement.headline
              .toLowerCase()
              .contains(normalizedQuery) ||
          community.announcement.body.toLowerCase().contains(normalizedQuery) ||
          community.groups.any((group) {
            return group.name.toLowerCase().contains(normalizedQuery) ||
                group.summary.toLowerCase().contains(normalizedQuery);
          });
    }).toList(growable: false);
  }

  List<CommunityContact> get visibleContacts {
    if (!_contactAccessStatus.hasAnyAccess) {
      return const <CommunityContact>[];
    }

    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return _contacts.where((contact) {
      final matchesFilter = switch (_contactFilter) {
        ContactListFilter.all => true,
        ContactListFilter.onWhatsWave => contact.isOnWhatsWave,
        ContactListFilter.invite => !contact.isOnWhatsWave,
      };
      if (!matchesFilter) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }

      return contact.name.toLowerCase().contains(normalizedQuery) ||
          contact.phoneNumber.toLowerCase().contains(normalizedQuery) ||
          contact.about.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
  }

  List<CommunityContact> get onWhatsWaveContacts => _contacts
      .where((contact) => contact.isOnWhatsWave)
      .toList(growable: false);

  Future<void> ensureLoaded() async {
    if (_isLoading) {
      return;
    }
    if (!_hasLoaded) {
      await loadOverview();
      return;
    }
    await syncContactsAccessStatus();
  }

  Future<void> loadOverview() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final overview = await _repository.fetchOverview();
      _communities = overview.communities;
      _contacts = overview.contacts;
      _hasLoaded = true;
      _contactAccessStatus = await _permissionService.contactAccessStatus();
      _listenForDeviceContactsChanges();
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load communities right now.';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refreshes on the OS's own contacts-database-changed notification, not
  /// just app resume (see NewChatScreen) -- notably more reliable for
  /// picking up an edited iOS limited-contacts selection, since that
  /// notification is driven by the actual native change event rather than
  /// inferred from foreground/background transitions.
  void _listenForDeviceContactsChanges() {
    if (_deviceContactsChangedSubscription != null) {
      return;
    }
    final stream = _repository.watchDeviceContactsChanged();
    if (stream == null) {
      return;
    }
    _deviceContactsChangedSubscription = stream.listen((_) {
      loadOverview();
    });
  }

  @override
  void dispose() {
    _deviceContactsChangedSubscription?.cancel();
    super.dispose();
  }

  Future<void> syncContactsAccessStatus() async {
    final accessStatus = await _permissionService.contactAccessStatus();
    if (_contactAccessStatus == accessStatus) {
      return;
    }

    _contactAccessStatus = accessStatus;
    notifyListeners();
  }

  void updateSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }

    _searchQuery = value;
    _errorMessage = null;
    notifyListeners();
  }

  void selectContactFilter(ContactListFilter filter) {
    if (_contactFilter == filter) {
      return;
    }

    _contactFilter = filter;
    notifyListeners();
  }

  void grantContactsAccess() {
    if (_contactAccessStatus == ContactAccessStatus.granted) {
      return;
    }

    _contactAccessStatus = ContactAccessStatus.granted;
    _errorMessage = null;
    notifyListeners();
  }

  void denyContactsAccess() {
    if (_contactAccessStatus == ContactAccessStatus.denied) {
      return;
    }

    _contactAccessStatus = ContactAccessStatus.denied;
    notifyListeners();
  }

  void resetContactsAccess() {
    if (_contactAccessStatus == ContactAccessStatus.unknown) {
      return;
    }

    _contactAccessStatus = ContactAccessStatus.unknown;
    notifyListeners();
  }

  Future<void> requestContactsAccess() async {
    if (_isRequestingContactsAccess) {
      return;
    }

    _isRequestingContactsAccess = true;
    _errorMessage = null;
    notifyListeners();

    _contactAccessStatus = await _permissionService.requestContactsAccess();

    _isRequestingContactsAccess = false;
    notifyListeners();
  }

  Future<void> openContactSettings() async {
    await _permissionService.openSettings();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  CommunityHub? communityById(String communityId) {
    for (final community in _communities) {
      if (community.id == communityId) {
        return community;
      }
    }
    return null;
  }

  /// Resolves the parent community when [threadId] backs a community
  /// announcements channel or one of its groups.
  CommunityThreadContext? communityContextForThread(String threadId) {
    for (final community in _communities) {
      if (community.announcementThreadId == threadId) {
        return CommunityThreadContext(
          community: community,
          isAnnouncement: true,
        );
      }
      for (final group in community.groups) {
        if (group.threadId == threadId) {
          return CommunityThreadContext(
            community: community,
            isAnnouncement: false,
          );
        }
      }
    }
    return null;
  }

  CommunityContact? contactById(String contactId) {
    for (final contact in _contacts) {
      if (contact.id == contactId) {
        return contact;
      }
    }
    return null;
  }

  /// This device's own address-book number for a matched user, or null.
  ///
  /// Only the profile owner's session can write `userProfiles/{uid}
  /// .phoneNumber`, so a contact who hasn't opened a build that writes it
  /// publishes no number at all and Contact info showed no number for them.
  /// The viewer's phone book already holds it -- that's how the contact was
  /// matched in the first place -- so this reads it back out. Empty when
  /// contacts were never loaded (e.g. permission not granted), which is
  /// exactly the "no number, no row" case.
  ///
  /// Matches [CommunityContact.id] too because demo threads carry no
  /// participantUid and fall back to their thread id, which is the slug the
  /// demo contacts are keyed by (same fallback as
  /// FakeChatRepository.fetchContactProfile).
  String? phoneNumberForUid(String uid) {
    for (final contact in _contacts) {
      if (contact.matchedUid == uid || contact.id == uid) {
        return contact.phoneNumber;
      }
    }
    return null;
  }

  bool isCommunityBusy(String communityId) =>
      _busyCommunityIds.contains(communityId);

  bool isContactBusy(String contactId) => _busyContactIds.contains(contactId);

  List<String> sharedCommunityNames(CommunityContact contact) {
    return _communities
        .where((community) => contact.memberCommunityIds.contains(community.id))
        .map((community) => community.title)
        .toList(growable: false);
  }

  Future<bool> createCommunity({
    required String title,
    required String description,
  }) async {
    if (_isCreatingCommunity) {
      return false;
    }

    _isCreatingCommunity = true;
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      final overview = await _repository.createCommunity(
        title: title,
        description: description,
      );
      _communities = overview.communities;
      _contacts = overview.contacts;
      didSucceed = true;
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not create that community right now.';
    }

    _isCreatingCommunity = false;
    notifyListeners();
    return didSucceed;
  }

  Future<void> openCommunity(String communityId) async {
    await _runCommunityMutation(
      communityId,
      () => _repository.markCommunityOpened(communityId),
      fallbackError: 'We could not open that community right now.',
    );
  }

  /// Deactivates [communityId] -- it leaves every member's list, its
  /// groups carry on as ordinary group chats, and its announcement group
  /// closes (https://faq.whatsapp.com/785738926054798). Cannot be undone.
  Future<bool> deactivateCommunity(String communityId) async {
    // Owner-only, not admin-only. Deactivation cannot be undone
    // (https://faq.whatsapp.com/785738926054798), while an admin role is
    // something an owner hands out (and takes back) for adding and removing
    // members and groups
    // (https://www.whatsapp.com/communities/learning/settingupyourcommunity)
    // -- so promoting someone must not also hand them a button that
    // destroys the community for everyone. The creator is the one member
    // who can never be demoted or removed, which is exactly the role an
    // irreversible action belongs to. Refusing here rather than waiting for
    // the backend keeps a member from being told a community is gone when
    // it is not.
    final community = communityById(communityId);
    if (community != null && !community.viewerIsOwner) {
      _errorMessage =
          'Only the person who created this community can deactivate it. '
          'You can exit it instead.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.deactivateCommunity(communityId),
      fallbackError: 'We could not delete that community right now.',
    );
  }

  /// Leaves [communityId] without touching it for anyone else.
  ///
  /// WhatsApp lets any member exit a community at any time -- exiting takes
  /// you out of the community and its announcement group while the
  /// community carries on (https://faq.whatsapp.com/1312647189536807). The
  /// admin who created it deactivates instead, which is why that case is
  /// turned back here.
  Future<bool> exitCommunity(String communityId) async {
    // Only the creator is turned back, not every admin: a promoted admin is
    // still a member, and WhatsApp guarantees every member a way out
    // (https://faq.whatsapp.com/1312647189536807) -- gating this on the
    // admin role instead would trap the very people an owner promoted.
    // Exiting also drops the leaver's admin role (see the repositories), and
    // the creator -- who is always an admin and cannot be demoted -- can
    // never take this path, so the admin roster can never empty out.
    final community = communityById(communityId);
    if (community != null && community.viewerIsOwner) {
      _errorMessage =
          'You created this community. Delete it instead of exiting.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.exitCommunity(communityId),
      fallbackError: 'We could not exit that community right now.',
    );
  }

  /// Promotes or demotes [memberUid] in [communityId].
  ///
  /// Admin-only, capped at [CommunityHub.maxAdmins]: "You can assign up to
  /// 20 community admin roles."
  /// (https://www.whatsapp.com/communities/learning/settingupyourcommunity).
  /// Nobody may act on their own row -- self-promotion is the hole that
  /// makes an admin list meaningless -- and the creator can never be
  /// demoted, which is what stops two admins from locking the owner out of
  /// their own community. `firestore.rules` enforces the same four.
  Future<bool> setCommunityAdmin({
    required String communityId,
    required String memberUid,
    required bool isAdmin,
  }) async {
    final community = communityById(communityId);
    if (community == null) {
      return false;
    }

    String? refusal;
    if (!community.viewerIsAdmin) {
      refusal = 'Only community admins can change admin roles.';
    } else if (memberUid == community.viewerUid) {
      refusal = 'You cannot change your own admin role.';
    } else if (!isAdmin && memberUid == community.ownerUid) {
      refusal = 'The person who created this community stays an admin.';
    } else if (isAdmin &&
        !community.isAdminUid(memberUid) &&
        community.hasMaxAdmins) {
      refusal = 'This community already has '
          '${CommunityHub.maxAdmins} admins. Dismiss one before adding '
          'another.';
    }
    if (refusal != null) {
      _errorMessage = refusal;
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.setCommunityAdmin(
        communityId: communityId,
        memberUid: memberUid,
        isAdmin: isAdmin,
      ),
      fallbackError: 'We could not change that admin role right now.',
    );
  }

  /// Renames [communityId]. Admin-only.
  Future<bool> renameCommunity({
    required String communityId,
    required String title,
  }) async {
    final community = communityById(communityId);
    if (community == null) {
      return false;
    }
    if (!community.viewerIsAdmin) {
      _errorMessage = 'Only community admins can edit this community.';
      notifyListeners();
      return false;
    }
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Enter a community name.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.renameCommunity(
        communityId: communityId,
        title: trimmed,
      ),
      fallbackError: 'We could not rename that community right now.',
    );
  }

  /// Updates the about text on [communityId]. Admin-only.
  Future<bool> updateCommunityDescription({
    required String communityId,
    required String description,
  }) async {
    final community = communityById(communityId);
    if (community == null) {
      return false;
    }
    if (!community.viewerIsAdmin) {
      _errorMessage = 'Only community admins can edit this community.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.updateCommunityDescription(
        communityId: communityId,
        description: description,
      ),
      fallbackError: 'We could not update that community right now.',
    );
  }

  Future<bool> updateCommunityAvatar({
    required String communityId,
    required File photo,
  }) async {
    final community = communityById(communityId);
    if (community == null) {
      return false;
    }
    if (!community.viewerIsAdmin) {
      _errorMessage = 'Only community admins can edit this community.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.updateCommunityAvatar(
        communityId: communityId,
        photo: photo,
      ),
      fallbackError: 'We could not update that community photo right now.',
    );
  }

  Future<bool> deleteCommunityAvatar(String communityId) async {
    final community = communityById(communityId);
    if (community == null) {
      return false;
    }
    if (!community.viewerIsAdmin) {
      _errorMessage = 'Only community admins can edit this community.';
      notifyListeners();
      return false;
    }

    return _runCommunityAction(
      communityId,
      () => _repository.deleteCommunityAvatar(communityId),
      fallbackError: 'We could not remove that community photo right now.',
    );
  }

  /// The address-book entry behind a community member's uid, if this device
  /// has one -- what puts a name and avatar on a members-list row.
  ///
  /// Matches [CommunityContact.id] as well as its matchedUid, because demo
  /// and fixture contacts carry no matchedUid and are keyed by their slug
  /// (same fallback as [phoneNumberForUid]).
  CommunityContact? contactForUid(String uid) {
    for (final contact in _contacts) {
      if (contact.matchedUid == uid || contact.id == uid) {
        return contact;
      }
    }
    return null;
  }

  Future<bool> _runCommunityAction(
    String communityId,
    Future<CommunitiesOverview> Function() action, {
    required String fallbackError,
  }) async {
    _busyCommunityIds.add(communityId);
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      final overview = await action();
      _communities = overview.communities;
      _contacts = overview.contacts;
      didSucceed = true;
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = fallbackError;
    }

    _busyCommunityIds.remove(communityId);
    notifyListeners();
    return didSucceed;
  }

  Future<bool> inviteContactToCommunity({
    required String communityId,
    required String contactId,
  }) async {
    _busyCommunityIds.add(communityId);
    _busyContactIds.add(contactId);
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      final overview = await _repository.inviteContactToCommunity(
        communityId: communityId,
        contactId: contactId,
      );
      _communities = overview.communities;
      _contacts = overview.contacts;
      didSucceed = true;
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not send that community invite right now.';
    }

    if (didSucceed) {
      await _ensureCommunityThreads(communityId);
    }

    _busyCommunityIds.remove(communityId);
    _busyContactIds.remove(contactId);
    notifyListeners();
    return didSucceed;
  }

  Future<void> _ensureCommunityThreads(String communityId) async {
    await _ensureAnnouncementThreadIfPossible(communityId);
    await _ensureGroupThreadIfPossible(communityId);
  }

  Future<void> _ensureAnnouncementThreadIfPossible(String communityId) async {
    final createThread = _createGroupThread;
    if (createThread == null) {
      return;
    }

    final community = communityById(communityId);
    if (community == null || community.announcementThreadId != null) {
      return;
    }

    final memberUids = _memberUidsForCommunity(communityId);
    if (memberUids.isEmpty) {
      return;
    }

    try {
      final threadId = await createThread(
        name: 'Announcements',
        memberUids: memberUids,
        isCommunityGroup: true,
        // Only the community admin creating this thread may post into it
        // -- it is created by the owner, so it is their uid that lands in
        // the thread's groupAdminUids and passes the firestore.rules
        // message-create gate. See ChatThread.isAnnouncementOnly.
        isAnnouncementOnly: true,
      );
      if (threadId == null) {
        return;
      }
      final overview = await _repository.attachAnnouncementThread(
        communityId: communityId,
        threadId: threadId,
      );
      _communities = overview.communities;
      _contacts = overview.contacts;
    } catch (_) {
      // Best-effort -- the invite itself already succeeded.
    }
  }

  /// Backs a community's first group with a real [ChatThread] as soon as it
  /// has at least one invited-or-member contact who's actually on WhatsWave
  /// (has a real uid) -- creating a thread with zero members isn't possible
  /// (ChatRepository.createGroup requires at least one), so a brand-new
  /// community's group starts with no thread until this fires. Failures
  /// here are swallowed rather than surfaced as _errorMessage -- the invite
  /// itself already succeeded, and messaging setup is best-effort.
  Future<void> _ensureGroupThreadIfPossible(String communityId) async {
    final createThread = _createGroupThread;
    if (createThread == null) {
      return;
    }

    final community = communityById(communityId);
    if (community == null || community.groups.isEmpty) {
      return;
    }
    final group = community.groups.first;
    if (group.threadId != null) {
      return;
    }

    final memberUids = _memberUidsForCommunity(communityId);
    if (memberUids.isEmpty) {
      return;
    }

    try {
      final threadId = await createThread(
        name: group.name,
        memberUids: memberUids,
        isCommunityGroup: true,
      );
      if (threadId == null) {
        return;
      }
      final overview = await _repository.attachGroupThread(
        communityId: communityId,
        groupId: group.id,
        threadId: threadId,
      );
      _communities = overview.communities;
      _contacts = overview.contacts;
    } catch (_) {
      // Best-effort -- the invite itself already succeeded.
    }
  }

  List<String> _memberUidsForCommunity(String communityId) {
    return <String>[
      for (final contact in _contacts)
        if (contact.matchedUid != null &&
            (contact.memberCommunityIds.contains(communityId) ||
                contact.pendingCommunityInviteIds.contains(communityId)))
          contact.matchedUid!,
    ];
  }

  Future<bool> shareAppInvite(String contactId) async {
    _busyContactIds.add(contactId);
    _errorMessage = null;
    notifyListeners();

    var didSucceed = false;
    try {
      final overview = await _repository.shareAppInvite(contactId);
      _communities = overview.communities;
      _contacts = overview.contacts;
      didSucceed = true;
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not prepare that invite link right now.';
    }

    _busyContactIds.remove(contactId);
    notifyListeners();
    return didSucceed;
  }

  Future<void> _runCommunityMutation(
    String communityId,
    Future<CommunitiesOverview> Function() action, {
    required String fallbackError,
  }) async {
    _busyCommunityIds.add(communityId);
    _errorMessage = null;
    notifyListeners();

    try {
      final overview = await action();
      _communities = overview.communities;
      _contacts = overview.contacts;
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = fallbackError;
    }

    _busyCommunityIds.remove(communityId);
    notifyListeners();
  }
}
