import 'package:flutter/material.dart';

import '../../../../core/crypto/safety_number_service.dart';

/// Shows the safety number two people compare to confirm nobody is in the
/// middle of their conversation.
///
/// Encryption without verification authenticates nothing: it proves
/// *somebody* holds the key, not that it is the person you think. This is
/// the only surface in the app where that can be checked, which is why it
/// ships with the encryption rather than after it.
///
/// Takes the digits as a future rather than the service that produces
/// them. The service reaches a database and an isolate, neither of which
/// resolves under the widget-test binding -- and a card that depends on
/// nothing but a string is the smaller dependency regardless.
class SafetyNumberCard extends StatelessWidget {
  const SafetyNumberCard({
    required this.safetyNumber,
    required this.contactName,
    this.identityChanged = false,
    super.key,
  });

  /// The digits, or null when this contact's identity key is unknown.
  final Future<String?> safetyNumber;
  final String contactName;

  /// Their identity key is not the one this device saw before.
  ///
  /// Either they reinstalled, or somebody is impersonating them. Nothing
  /// in the protocol can distinguish those, so the user is told plainly
  /// and asked to re-compare -- quietly accepting the new key is what a
  /// man-in-the-middle relies on.
  final bool identityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String?>(
      future: safetyNumber,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final digits = snapshot.data;
        if (digits == null) {
          // They have no published identity yet. Showing nothing beats
          // showing a number that verifies nothing.
          return const SizedBox.shrink();
        }

        return Padding(
          key: const Key('safety_number_card'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      // Flexible and wrapping, never a fixed height: this
                      // must survive a 200% text scale on a compact phone
                      // (docs/ui_layout_guidelines.md).
                      Flexible(
                        child: Text(
                          'Safety number',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    SafetyNumberService.format(digits),
                    key: const Key('safety_number_digits'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      // Tabular figures so the groups line up in columns,
                      // which is what makes reading them aloud workable.
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                      letterSpacing: 1.1,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (identityChanged) ...[
                    Container(
                      key: const Key('safety_number_changed_warning'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'This safety number changed. $contactName may '
                              'have reinstalled, or someone could be '
                              'intercepting your messages. Compare the '
                              'digits again before sending anything '
                              'sensitive.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Compare these digits with $contactName in person or '
                    'over a call you trust. If they match, nobody is '
                    'reading your messages in between.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
