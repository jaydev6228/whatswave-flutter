import 'package:flutter/material.dart';

import '../../../core/controllers/app_preferences_controller.dart';
import '../../chats/application/chats_controller.dart';
import '../../chats/domain/chat_attachment.dart';
import 'widgets/settings_tile.dart';

const double _kStorageScreenHorizontalPadding = 16;

/// Real, computed media counts across every chat, plus the media
/// auto-download preference -- WhatsApp's own "Storage and data" screen,
/// scoped to what this app can actually report (no OS-level disk usage
/// API here, so this counts attachments rather than claiming a byte size
/// this app has no way to measure accurately).
class StorageDataScreen extends StatelessWidget {
  const StorageDataScreen({
    required this.chatsController,
    required this.preferencesController,
    super.key,
  });

  final ChatsController chatsController;
  final AppPreferencesController preferencesController;

  Map<ChatAttachmentType, int> _mediaCounts() {
    final counts = <ChatAttachmentType, int>{};
    for (final thread in chatsController.threads) {
      for (final message in thread.messages) {
        for (final attachment in message.attachments) {
          counts[attachment.type] = (counts[attachment.type] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([chatsController, preferencesController]),
      builder: (context, _) {
        final counts = _mediaCounts();
        final totalItems = counts.values.fold<int>(0, (a, b) => a + b);
        return Scaffold(
          key: const Key('storage_data_screen'),
          appBar: AppBar(
            title: const Text(
              'Storage and data',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                _kStorageScreenHorizontalPadding,
                12,
                _kStorageScreenHorizontalPadding,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Text(
                  'Media usage',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  totalItems == 0
                      ? 'No media in your chats yet.'
                      : '$totalItems item${totalItems == 1 ? '' : 's'} across all chats.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                  ),
                ),
                const SizedBox(height: 12),
                _MediaUsageCard(counts: counts),
                const SizedBox(height: 12),
                Text(
                  'Network usage',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.24),
                    ),
                  ),
                  child: SettingsTile(
                    key: const Key('storage_auto_download_tile'),
                    icon: Icons.download_for_offline_outlined,
                    title: 'Auto-download media',
                    subtitle: preferencesController.mediaAutoDownloadEnabled
                        ? 'Photos, videos, and files download automatically.'
                        : 'Media only downloads when you tap it.',
                    trailing: Switch.adaptive(
                      key: const Key('storage_auto_download_switch'),
                      value: preferencesController.mediaAutoDownloadEnabled,
                      onChanged:
                          preferencesController.setMediaAutoDownloadEnabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MediaUsageCard extends StatelessWidget {
  const _MediaUsageCard({required this.counts});

  final Map<ChatAttachmentType, int> counts;

  static const _rows = <(ChatAttachmentType, IconData, String)>[
    (ChatAttachmentType.photo, Icons.photo_outlined, 'Photos'),
    (ChatAttachmentType.video, Icons.videocam_outlined, 'Videos'),
    (ChatAttachmentType.file, Icons.description_outlined, 'Documents'),
    (ChatAttachmentType.voiceNote, Icons.mic_none_outlined, 'Voice notes'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
              ),
            _MediaUsageRow(
              icon: _rows[i].$2,
              label: _rows[i].$3,
              count: counts[_rows[i].$1] ?? 0,
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaUsageRow extends StatelessWidget {
  const _MediaUsageRow({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
