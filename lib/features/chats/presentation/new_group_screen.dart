import 'package:flutter/material.dart';

import '../../communities/application/communities_controller.dart';
import '../../communities/domain/community_contact.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/search_field.dart';
import '../application/chats_controller.dart';

/// Two-step group creation: select members, then name the group. Pops with
/// the new thread's id on success so the caller (NewChatScreen) can bubble
/// it further up to ChatsScreen, which opens the conversation.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({
    required this.communitiesController,
    required this.chatsController,
    super.key,
  });

  final CommunitiesController communitiesController;
  final ChatsController chatsController;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  late final TextEditingController _searchController;
  late final TextEditingController _nameController;
  final Set<String> _selectedContactIds = <String>{};
  bool _showNameStep = false;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // Only contacts with a real uid can be added to a real Firestore group --
  // matches the same restriction Calls/Message already apply elsewhere.
  List<CommunityContact> get _eligibleContacts => widget
      .communitiesController.onWhatsWaveContacts
      .where((contact) => contact.matchedUid != null)
      .toList(growable: false);

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

  void _goToNameStep() {
    if (_selectedContactIds.isEmpty) {
      return;
    }
    setState(() => _showNameStep = true);
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Give the group a name.');
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    final memberUids = _eligibleContacts
        .where((contact) => _selectedContactIds.contains(contact.id))
        .map((contact) => contact.matchedUid!)
        .toList(growable: false);

    final threadId = await widget.chatsController.createGroup(
      name: name,
      memberUids: memberUids,
    );

    if (!mounted) {
      return;
    }

    if (threadId == null) {
      setState(() {
        _isCreating = false;
        _errorMessage = widget.chatsController.errorMessage ??
            'We could not create that group right now.';
      });
      widget.chatsController.clearError();
      return;
    }

    Navigator.of(context).pop(threadId);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showNameStep,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showNameStep) {
          setState(() => _showNameStep = false);
        }
      },
      child:
          _showNameStep ? _buildNameStep(context) : _buildMemberStep(context),
    );
  }

  Widget _buildMemberStep(BuildContext context) {
    final contacts = _filteredContacts;

    return Scaffold(
      key: const Key('new_group_members_screen'),
      appBar: AppBar(
        title: Text(
          _selectedContactIds.isEmpty
              ? 'Add members'
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
                    fieldKey: const Key('new_group_search_field'),
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
                                'Only contacts already on WhatsWave can join a group.',
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
                              key: Key('new_group_member_${contact.id}'),
                              value: isSelected,
                              onChanged: (_) => _toggleContact(contact.id),
                              controlAffinity:
                                  ListTileControlAffinity.trailing,
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
              key: const Key('new_group_next_button'),
              onPressed: _goToNameStep,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Next'),
            ),
    );
  }

  Widget _buildNameStep(BuildContext context) {
    final theme = Theme.of(context);
    final memberCount = _selectedContactIds.length;

    return Scaffold(
      key: const Key('new_group_details_screen'),
      appBar: AppBar(
        title: const Text('New group', maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          key: const Key('new_group_back_to_members'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() => _showNameStep = false),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: AvatarBadge(
                  label: _previewAvatarLabel(),
                  color: theme.colorScheme.primary,
                  size: 72,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('new_group_name_field'),
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Group name'),
                onSubmitted: (_) {
                  if (!_isCreating) {
                    _createGroup();
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                memberCount == 1
                    ? '1 member selected'
                    : '$memberCount members selected',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('new_group_create_button'),
                  onPressed: _isCreating ? null : _createGroup,
                  child: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewAvatarLabel() {
    final trimmed = _nameController.text.trim();
    return trimmed.isEmpty ? 'GR' : trimmed[0].toUpperCase();
  }
}
