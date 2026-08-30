import 'package:flutter/material.dart';

import '../../communities/application/communities_controller.dart';
import '../../communities/domain/community_contact.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/search_field.dart';
import '../domain/chat_thread.dart';

/// Multi-select contact picker for adding members to an existing group --
/// the "Add participants" step in group info, distinct from
/// [NewGroupScreen]'s own member-select step (which creates a brand new
/// group rather than growing one). Pops with the picked uids, or null if
/// cancelled.
class AddGroupMembersScreen extends StatefulWidget {
  const AddGroupMembersScreen({
    required this.communitiesController,
    required this.thread,
    super.key,
  });

  final CommunitiesController communitiesController;
  final ChatThread thread;

  @override
  State<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<AddGroupMembersScreen> {
  final _searchController = TextEditingController();
  final Set<String> _selectedContactIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CommunityContact> get _eligibleContacts {
    final existingUids =
        widget.thread.participants?.map((p) => p.uid).toSet() ?? <String>{};
    return widget.communitiesController.onWhatsWaveContacts
        .where((contact) =>
            contact.matchedUid != null &&
            !existingUids.contains(contact.matchedUid))
        .toList(growable: false);
  }

  List<CommunityContact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    final contacts = _eligibleContacts;
    if (query.isEmpty) {
      return contacts;
    }
    return contacts
        .where((contact) => contact.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _toggleContact(String contactId) {
    setState(() {
      if (_selectedContactIds.contains(contactId)) {
        _selectedContactIds.remove(contactId);
      } else {
        _selectedContactIds.add(contactId);
      }
    });
  }

  void _confirm() {
    final memberUids = _eligibleContacts
        .where((contact) => _selectedContactIds.contains(contact.id))
        .map((contact) => contact.matchedUid!)
        .toList(growable: false);
    Navigator.of(context).pop<List<String>>(memberUids);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;

    return Scaffold(
      key: const Key('add_group_members_screen'),
      appBar: AppBar(
        title: Text(
          _selectedContactIds.isEmpty
              ? 'Add participants'
              : '${_selectedContactIds.length} selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: widget.communitiesController,
          builder: (context, _) {
            final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SearchField(
                    fieldKey: const Key('add_group_members_search_field'),
                    controller: _searchController,
                    hintText: 'Search contacts',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: contacts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: EmptyStateCard(
                            icon: Icons.person_search_outlined,
                            title: 'No contacts to add',
                            message:
                                'Everyone already on WhatsWave here is already in this group.',
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            bottom: 96 + bottomSafeInset,
                          ),
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            final contact = contacts[index];
                            final isSelected =
                                _selectedContactIds.contains(contact.id);
                            return CheckboxListTile(
                              key: Key('add_group_member_${contact.id}'),
                              value: isSelected,
                              onChanged: (_) => _toggleContact(contact.id),
                              controlAffinity: ListTileControlAffinity.trailing,
                              secondary: AvatarBadge(
                                label: contact.avatarLabel,
                                color: contact.accentColor,
                                size: 44,
                              ),
                              title: Text(
                                contact.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _selectedContactIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('add_group_members_confirm_button'),
              onPressed: _confirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Add'),
            ),
    );
  }
}

Future<List<String>?> pickGroupMembersToAdd(
  BuildContext context, {
  required CommunitiesController communitiesController,
  required ChatThread thread,
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => AddGroupMembersScreen(
        communitiesController: communitiesController,
        thread: thread,
      ),
    ),
  );
}
