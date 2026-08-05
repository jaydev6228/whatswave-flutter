import 'package:flutter/material.dart';

import '../../../core/permissions/app_permission_service.dart';
import '../data/communities_overview.dart';
import '../data/communities_repository.dart';
import '../domain/community_contact.dart';
import '../domain/community_hub.dart';
import '../domain/contact_access_status.dart';

enum CommunityListFilter { all, unread, announcements }

enum ContactListFilter { all, onWhatsWave, invite }

class CommunitiesController extends ChangeNotifier {
  CommunitiesController({
    required CommunitiesRepository repository,
    AppPermissionService? permissionService,
  })  : _repository = repository,
        _permissionService = permissionService ?? MemoryAppPermissionService();

  final CommunitiesRepository _repository;
  final AppPermissionService _permissionService;

  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _isCreatingCommunity = false;
  bool _isRequestingContactsAccess = false;
  String? _errorMessage;
  String _searchQuery = '';
  CommunityListFilter _communityFilter = CommunityListFilter.all;
  ContactListFilter _contactFilter = ContactListFilter.all;
  ContactAccessStatus _contactAccessStatus = ContactAccessStatus.unknown;
  List<CommunityHub> _communities = const <CommunityHub>[];
  List<CommunityContact> _contacts = const <CommunityContact>[];
  final Set<String> _busyCommunityIds = <String>{};
  final Set<String> _busyContactIds = <String>{};

  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;
  bool get isCreatingCommunity => _isCreatingCommunity;
  bool get isRequestingContactsAccess => _isRequestingContactsAccess;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  CommunityListFilter get communityFilter => _communityFilter;
  ContactListFilter get contactFilter => _contactFilter;
  ContactAccessStatus get contactAccessStatus => _contactAccessStatus;
  List<CommunityHub> get communities =>
      List<CommunityHub>.unmodifiable(_communities);
  List<CommunityContact> get contacts =>
      List<CommunityContact>.unmodifiable(_contacts);

  List<CommunityHub> get visibleCommunities {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return _communities.where((community) {
      final matchesFilter = switch (_communityFilter) {
        CommunityListFilter.all => true,
        CommunityListFilter.unread => community.hasUnread,
        CommunityListFilter.announcements => community.hasFreshAnnouncement,
      };
      if (!matchesFilter) {
        return false;
      }
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
    } on CommunitiesRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'We could not load communities right now.';
    }

    _isLoading = false;
    notifyListeners();
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

  void selectCommunityFilter(CommunityListFilter filter) {
    if (_communityFilter == filter) {
      return;
    }

    _communityFilter = filter;
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

  CommunityContact? contactById(String contactId) {
    for (final contact in _contacts) {
      if (contact.id == contactId) {
        return contact;
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

    _busyCommunityIds.remove(communityId);
    _busyContactIds.remove(contactId);
    notifyListeners();
    return didSucceed;
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
