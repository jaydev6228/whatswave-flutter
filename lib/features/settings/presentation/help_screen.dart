import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const double _kHelpScreenHorizontalPadding = 16;

class _HelpTopic {
  const _HelpTopic(this.question, this.answer);

  final String question;
  final String answer;
}

const _helpTopics = <_HelpTopic>[
  _HelpTopic(
    'How do I manage a group?',
    'Open the group, tap its name to reach Group info, then use "Add '
        'participants" or tap a member to promote them to admin or remove '
        'them. Only admins can rename the group, edit its description, or '
        'manage membership.',
  ),
  _HelpTopic(
    'Where do starred messages go?',
    'Tap and hold any message and choose Star. Every starred message '
        'across all your chats is collected under Settings > Chats > '
        'Starred messages.',
  ),
  _HelpTopic(
    'Can I search inside a single chat?',
    'Yes -- open the chat and tap the search icon in the header to search '
        'that conversation\'s messages, with up/down arrows to jump '
        'between matches.',
  ),
  _HelpTopic(
    'Who can see my status updates?',
    'Go to Settings > Privacy center to choose who can see your status, '
        'last seen, and profile photo -- everyone, your contacts, or '
        'nobody.',
  ),
  _HelpTopic(
    'How do I stop a message from being seen by everyone?',
    'Tap and hold a message you sent and choose "Delete for everyone" to '
        'remove it for all participants, or "Delete for me" to remove it '
        'only from your own view.',
  ),
  _HelpTopic(
    'Why can\'t I message someone?',
    'You may have blocked them, or they may have blocked you. Check '
        'Settings > Chats and each contact\'s info screen for a Block/'
        'Unblock option.',
  ),
];

/// Static FAQ + a real "Contact support" mailto link -- WhatsApp's own
/// Help screen, scoped to what this app can genuinely offer (no backing
/// support ticket system to wire up).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _contactSupport(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@whatswave.app',
      queryParameters: {'subject': 'WhatsWave support'},
    );
    final didLaunch =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!didLaunch && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app is set up on this device.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('help_screen'),
      appBar: AppBar(
        title: const Text('Help', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            _kHelpScreenHorizontalPadding,
            12,
            _kHelpScreenHorizontalPadding,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              'Frequently asked questions',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Material(
              // Not a Container+BoxDecoration here -- ExpansionTile's
              // internal ListTile paints its background/ink splash on the
              // nearest Material ancestor, so a colored DecoratedBox
              // between it and that ancestor would silently hide both.
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.24),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _helpTopics.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.24),
                        ),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: Key('help_topic_$i'),
                          title: Text(
                            _helpTopics[i].question,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          expandedAlignment: Alignment.centerLeft,
                          children: [
                            Text(
                              _helpTopics[i].answer,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.78),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Still need help?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('help_contact_support_button'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _contactSupport(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contact support',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'support@whatswave.app',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.64),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
