import 'package:flutter/material.dart';

import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/search_field.dart';
import '../application/chats_controller.dart';

/// A single-pick "Forward to" list -- taps a thread and pops with its id,
/// same pattern as the rest of this app's picker screens (e.g.
/// NewChatScreen). No multi-select yet -- forwarding to several chats at
/// once is a real WhatsApp feature this doesn't cover, only forwarding to
/// one chat at a time.
class ForwardMessageScreen extends StatefulWidget {
  const ForwardMessageScreen({
    required this.controller,
    this.excludeThreadId,
    super.key,
  });

  final ChatsController controller;

  /// The thread the message is already in -- forwarding it back into the
  /// same conversation isn't useful, so it's left out of the list.
  final String? excludeThreadId;

  @override
  State<ForwardMessageScreen> createState() => _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final threads = widget.controller.threads
        .where((thread) => thread.id != widget.excludeThreadId)
        .where((thread) =>
            query.isEmpty || thread.name.toLowerCase().contains(query))
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      key: const Key('forward_message_screen'),
      appBar: AppBar(
        title: const Text(
          'Forward to',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchField(
                fieldKey: const Key('forward_message_search_field'),
                controller: _searchController,
                hintText: 'Search chats',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: threads.isEmpty
                  ? Center(
                      child: Text(
                        'No chats to forward to.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: threads.length,
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        return ListTile(
                          key: Key('forward_target_${thread.id}'),
                          leading: AvatarBadge(
                            label: thread.avatarLabel,
                            color: thread.accentColor,
                            avatarUrl: thread.avatarUrl,
                            size: 44,
                          ),
                          title: Text(
                            thread.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              Navigator.of(context).pop<String>(thread.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> pickForwardTarget(
  BuildContext context, {
  required ChatsController controller,
  String? excludeThreadId,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => ForwardMessageScreen(
        controller: controller,
        excludeThreadId: excludeThreadId,
      ),
    ),
  );
}
