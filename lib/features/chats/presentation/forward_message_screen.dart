import 'package:flutter/material.dart';

import '../../shared/widgets/avatar_badge.dart';
import '../../shared/widgets/search_field.dart';
import '../application/chats_controller.dart';

/// A multi-select "Forward to" list -- pick any number of chats, then
/// confirm with the FAB, matching WhatsApp's ability to forward one
/// message to several chats in a single action.
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
  final Set<String> _selectedThreadIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleThread(String threadId) {
    setState(() {
      if (_selectedThreadIds.contains(threadId)) {
        _selectedThreadIds.remove(threadId);
      } else {
        _selectedThreadIds.add(threadId);
      }
    });
  }

  void _confirm() {
    Navigator.of(context)
        .pop<List<String>>(_selectedThreadIds.toList(growable: false));
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
        title: Text(
          _selectedThreadIds.isEmpty
              ? 'Forward to'
              : '${_selectedThreadIds.length} selected',
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
                      padding: EdgeInsets.only(
                        bottom: 96 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: threads.length,
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        final isSelected =
                            _selectedThreadIds.contains(thread.id);
                        return CheckboxListTile(
                          key: Key('forward_target_${thread.id}'),
                          value: isSelected,
                          onChanged: (_) => _toggleThread(thread.id),
                          controlAffinity: ListTileControlAffinity.trailing,
                          secondary: AvatarBadge(
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
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedThreadIds.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('forward_message_send_button'),
              onPressed: _confirm,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                _selectedThreadIds.length == 1 ? 'Send' : 'Send to all',
              ),
            ),
    );
  }
}

Future<List<String>?> pickForwardTarget(
  BuildContext context, {
  required ChatsController controller,
  String? excludeThreadId,
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => ForwardMessageScreen(
        controller: controller,
        excludeThreadId: excludeThreadId,
      ),
    ),
  );
}
