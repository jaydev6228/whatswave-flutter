import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calls/application/calls_controller.dart';
import '../../calls/domain/call_contact.dart';
import '../../calls/domain/call_history_entry.dart';
import '../../calls/presentation/call_experience_screen.dart';
import '../../communities/application/communities_controller.dart';
import '../../communities/domain/app_invite_link.dart';
import '../../communities/domain/community_contact.dart';
import '../../communities/domain/contact_access_status.dart';
import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/search_field.dart';
import '../application/chats_controller.dart';
import 'new_group_screen.dart';
import 'package:whatswave/features/shared/widgets/liquid_glass.dart';

/// The Chats tab's "+" destination -- combines starting a new group with
/// browsing contacts (message/call/video for people already on WhatsWave,
/// invite for people who aren't yet). Moved here from the Communities tab,
/// which is now purely about creating/managing communities themselves.
///
/// Resolves (via Navigator.pop) to a thread id once the caller has
/// something to open -- either an existing/started 1:1 thread or a freshly
/// created group -- so ChatsScreen is the single place that pushes
/// ConversationScreen, keeping the back stack at "Chats -> conversation"
/// instead of leaving this picker behind it.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({
    required this.communitiesController,
    required this.chatsController,
    required this.callsController,
    super.key,
  });

  final CommunitiesController communitiesController;
  final ChatsController chatsController;
  final CallsController callsController;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
    widget.communitiesController.ensureLoaded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // Editing the OS's limited-contacts selection happens in Settings, not
  // this app -- there's no callback for "the user changed something over
  // there", so the only signal available is coming back to the foreground.
  // Re-fetching on every resume (not just after tapping "Add more
  // contacts") also covers the user backgrounding the app for any other
  // reason while this screen is open.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.communitiesController.loadOverview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.communitiesController;
    final theme = Theme.of(context);

    return Scaffold(
      key: const Key('new_chat_screen'),
      appBar: AppBar(
        title: const Text(
          'New chat',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
            final query = _searchController.text.trim().toLowerCase();
            final contacts = controller.contacts.where((contact) {
              if (query.isEmpty) {
                return true;
              }
              return contact.name.toLowerCase().contains(query) ||
                  contact.phoneNumber.toLowerCase().contains(query);
            }).toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

            final onWhatsWave =
                contacts.where((c) => c.isOnWhatsWave).toList(growable: false);
            final needsInvite =
                contacts.where((c) => !c.isOnWhatsWave).toList(growable: false);
            final hasAccess = controller.contactAccessStatus.hasAnyAccess;
            final hasLimitedAccess =
                controller.contactAccessStatus == ContactAccessStatus.limited;

            return CustomScrollView(
              key: const PageStorageKey<String>('new_chat_scroll_view'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: SearchField(
                      fieldKey: const Key('new_chat_search_field'),
                      controller: _searchController,
                      hintText: 'Search name or number',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _NewGroupListTile(onTap: _openNewGroup),
                ),
                SliverToBoxAdapter(
                  child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.22),
                  ),
                ),
                if (hasLimitedAccess)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _LimitedContactsBanner(controller: controller),
                    ),
                  ),
                if (!hasAccess)
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverToBoxAdapter(
                      child: _ContactsAccessGate(controller: controller),
                    ),
                  )
                else if (contacts.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverToBoxAdapter(
                      child: EmptyStateCard(
                        icon: Icons.person_search_outlined,
                        title: query.isEmpty
                            ? 'No contacts yet'
                            : 'No matching contacts',
                        message: query.isEmpty
                            ? 'Contacts will show up here once they are available.'
                            : 'Try another name or number.',
                      ),
                    ),
                  )
                else ...[
                  if (onWhatsWave.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionLabel('On WhatsWave'),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final contact = onWhatsWave[index];
                          return _ContactTile(
                            contact: contact,
                            isBusy: controller.isContactBusy(contact.id),
                            onMessage: () => _openContact(contact),
                            onCall: (type) => _callContact(contact, type),
                          );
                        },
                        childCount: onWhatsWave.length,
                      ),
                    ),
                  ],
                  if (needsInvite.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: _SectionLabel('Invite to WhatsWave'),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final contact = needsInvite[index];
                          return _InviteContactTile(
                            contact: contact,
                            isBusy: controller.isContactBusy(contact.id),
                            onInvite: () => _shareInvite(contact),
                          );
                        },
                        childCount: needsInvite.length,
                      ),
                    ),
                  ],
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: 24 + bottomSafeInset),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openNewGroup() async {
    final threadId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => NewGroupScreen(
          communitiesController: widget.communitiesController,
          chatsController: widget.chatsController,
        ),
      ),
    );
    if (!mounted || threadId == null) {
      return;
    }
    Navigator.of(context).pop(threadId);
  }

  Future<void> _openContact(CommunityContact contact) async {
    final matchedUid = contact.matchedUid;
    if (matchedUid == null) {
      return;
    }

    final threadId = await widget.chatsController.startThreadWith(
      participantUid: matchedUid,
      participantName: contact.name,
      avatarLabel: contact.avatarLabel,
      accentColor: contact.accentColor,
    );
    if (!mounted) {
      return;
    }
    if (threadId == null) {
      await showErrorDialog(
        context,
        widget.chatsController.errorMessage ??
            'We could not start that chat right now.',
      );
      widget.chatsController.clearError();
      return;
    }

    Navigator.of(context).pop(threadId);
  }

  Future<void> _callContact(CommunityContact contact, CallType type) async {
    final matchedUid = contact.matchedUid;
    if (matchedUid == null) {
      return;
    }

    final started = await widget.callsController.startOutgoingCall(
      contact: CallContact(
        id: matchedUid,
        name: contact.name,
        avatarLabel: contact.avatarLabel,
        accentColor: contact.accentColor,
        photoAssetPath: null,
        uid: matchedUid,
      ),
      type: type,
    );
    if (!started || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CallExperienceScreen(controller: widget.callsController),
      ),
    );
  }

  Future<void> _shareInvite(CommunityContact contact) async {
    final inviteLink = buildCommunityAppInviteLink(contact);
    final didPrepareInvite =
        await widget.communitiesController.shareAppInvite(contact.id);
    if (!mounted) {
      return;
    }
    if (!didPrepareInvite) {
      final message = widget.communitiesController.errorMessage;
      if (message != null) {
        await showErrorDialog(context, message);
        widget.communitiesController.clearError();
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LiquidGlassDialog(
          title: Text('Invite ${contact.name}'),
          content: SelectableText(inviteLink),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

class _NewGroupListTile extends StatelessWidget {
  const _NewGroupListTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: const Key('new_chat_new_group'),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.groups_2_rounded,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: const Text(
        'New group',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isBusy,
    required this.onMessage,
    required this.onCall,
  });

  final CommunityContact contact;
  final bool isBusy;
  final VoidCallback onMessage;
  final void Function(CallType type) onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canReach = contact.matchedUid != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('new_chat_contact_${contact.id}'),
        onTap: isBusy || !canReach ? null : onMessage,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AvatarBadge(
                label: contact.avatarLabel,
                color: contact.accentColor,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.about.isEmpty
                          ? contact.phoneNumber
                          : contact.about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
              if (canReach) ...[
                // The app's glass buttons rather than bare Material icons,
                // so this list matches the chrome used everywhere else.
                LiquidGlassIconButton(
                  actionKey: Key('new_chat_call_audio_${contact.id}'),
                  tooltip: 'Voice call',
                  icon: Icons.call_outlined,
                  // visualSize, not size: size floors to a 48pt tap target,
                  // so anything smaller passed there draws identically.
                  visualSize: 40,
                  iconSize: 19,
                  onTap: isBusy ? null : () => onCall(CallType.audio),
                ),
                const SizedBox(width: 6),
                LiquidGlassIconButton(
                  actionKey: Key('new_chat_call_video_${contact.id}'),
                  tooltip: 'Video call',
                  icon: Icons.videocam_outlined,
                  visualSize: 40,
                  iconSize: 19,
                  onTap: isBusy ? null : () => onCall(CallType.video),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteContactTile extends StatelessWidget {
  const _InviteContactTile({
    required this.contact,
    required this.isBusy,
    required this.onInvite,
  });

  final CommunityContact contact;
  final bool isBusy;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          AvatarBadge(
            label: contact.avatarLabel,
            color: contact.accentColor,
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  contact.phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Outlined capsule, the same treatment the dialogs use for their
          // secondary actions -- a filled tonal button was the last piece of
          // stock Material styling left on this screen.
          TextButton(
            key: Key('new_chat_invite_${contact.id}'),
            onPressed: isBusy || contact.appInviteSent ? null : onInvite,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              // The chrome recipe: a translucent fill under a hairline, not
              // an outline on nothing -- an outline alone read as a different
              // material from the glass controls beside it.
              foregroundColor: theme.colorScheme.onSurface,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.08),
              textStyle: theme.textTheme.labelLarge,
              shape: StadiumBorder(
                side: BorderSide(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.16),
                ),
              ),
            ),
            child: Text(contact.appInviteSent ? 'Invited' : 'Invite'),
          ),
        ],
      ),
    );
  }
}

/// Shown when the OS granted access to only a hand-picked subset of
/// contacts (iOS's "Select Contacts..." choice) rather than the full
/// address book -- there's no in-app API to reopen that picker directly,
/// so this routes to the system Settings page instead, where the user can
/// edit which contacts are shared.
class _LimitedContactsBanner extends StatelessWidget {
  const _LimitedContactsBanner({required this.controller});

  final CommunitiesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.contact_phone_outlined,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Only some contacts are shared',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'You picked a limited set of contacts to share. Add more from your device settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('new_chat_manage_contacts_button'),
                    onPressed: controller.openContactSettings,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                    ),
                    child: const Text('Add more contacts'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactsAccessGate extends StatelessWidget {
  const _ContactsAccessGate({required this.controller});

  final CommunitiesController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmptyStateCard(
          icon: Icons.contact_phone_outlined,
          title: controller.contactAccessStatus == ContactAccessStatus.denied
              ? 'Contacts access is off'
              : 'Contacts are hidden for now',
          message: controller.contactAccessStatus == ContactAccessStatus.denied
              ? 'Turn contacts back on in system settings to message or invite people from your address book.'
              : 'Allow contacts to see who is already on WhatsWave and invite everyone else.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const Key('new_chat_contacts_allow'),
              onPressed: controller.isRequestingContactsAccess
                  ? null
                  : controller.requestContactsAccess,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                controller.isRequestingContactsAccess
                    ? 'Checking...'
                    : 'Allow contacts',
              ),
            ),
            if (controller.contactAccessStatus == ContactAccessStatus.denied)
              OutlinedButton(
                key: const Key('new_chat_contacts_settings'),
                onPressed: controller.openContactSettings,
                child: const Text('Open settings'),
              ),
          ],
        ),
      ],
    );
  }
}
