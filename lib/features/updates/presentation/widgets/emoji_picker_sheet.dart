import 'package:flutter/material.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

class EmojiCategory {
  const EmojiCategory({required this.label, required this.emoji});

  final String label;
  final List<String> emoji;
}

const List<String> _emojiFontFallback = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];

String? _preferredEmojiFontFamily(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
    TargetPlatform.android || TargetPlatform.linux => 'Noto Color Emoji',
    TargetPlatform.windows => 'Segoe UI Emoji',
    TargetPlatform.fuchsia => null,
  };
}

TextStyle emojiPreviewTextStyle(
  BuildContext context, {
  required double fontSize,
}) {
  return TextStyle(
    inherit: false,
    fontSize: fontSize,
    fontFamily: _preferredEmojiFontFamily(Theme.of(context).platform),
    fontFamilyFallback: _emojiFontFallback,
  );
}

bool usesTwemoji(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

// A curated slice of the device's own emoji font, not the full ~3600-glyph
// Unicode catalog (most of that tail is rare regional flags/obscure symbols
// not worth the Twemoji asset bloat -- see the matching
// `flutter_twemoji: includes:` allowlist in pubspec.yaml, which must stay in
// sync with every emoji listed here for iOS/macOS rendering to work).
const List<EmojiCategory> kStatusEmojiCategories = <EmojiCategory>[
  EmojiCategory(
    label: 'Smileys',
    emoji: <String>[
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '😚',
      '😙',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
    ],
  ),
  EmojiCategory(
    label: 'Gestures',
    emoji: <String>[
      '👍',
      '👎',
      '👏',
      '🙌',
      '🤝',
      '🙏',
      '💪',
      '👊',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '👌',
      '🤙',
      '👋',
      '🖐️',
      '🫶',
      '💃',
      '🕺',
      '🤳',
    ],
  ),
  EmojiCategory(
    label: 'Hearts',
    emoji: <String>[
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '💕',
      '💖',
    ],
  ),
  EmojiCategory(
    label: 'Nature',
    emoji: <String>[
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🦋',
      '🌸',
      '☀️',
      '🌤️',
      '⛅',
      '🌧️',
      '⛈️',
      '❄️',
      '🌈',
      '🌙',
      '⭐',
      '🌟',
    ],
  ),
  EmojiCategory(
    label: 'Food',
    emoji: <String>[
      '🍏',
      '🍎',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🍕',
      '🍔',
      '🍟',
      '🌭',
      '🍿',
      '🍩',
      '🍪',
      '🎂',
      '🍰',
      '🍫',
      '☕️',
      '🍵',
    ],
  ),
  EmojiCategory(
    label: 'Activities',
    emoji: <String>[
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🎾',
      '🏐',
      '🎱',
      '🏓',
      '🎮',
      '🎧',
      '🎸',
      '🎨',
      '✈️',
      '🚗',
      '🚕',
      '🚀',
      '⛵',
      '🏝️',
      '🗺️',
      '📍',
    ],
  ),
  EmojiCategory(
    label: 'Objects & symbols',
    emoji: <String>[
      '💯',
      '🔥',
      '✨',
      '💫',
      '💥',
      '💢',
      '💦',
      '💨',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
      '🏆',
      '🏅',
      '🎯',
      '💡',
      '📸',
      '🎬',
      '🎵',
      '🎶',
      '🔔',
      '💤',
      '⏰',
      '✔️',
      '❌',
      '❓',
      '❗',
      '⚡',
      '🔴',
      '🟢',
    ],
  ),
];

/// Bottom sheet for picking one emoji to place as an overlay -- shared by
/// the media composer and the text-status composer so both offer the same
/// full, categorized emoji set (matching WhatsApp's own "add an emoji"
/// action) instead of two divergent hand-picked lists.
class EmojiPickerSheet extends StatelessWidget {
  const EmojiPickerSheet({
    this.emojiCategories = kStatusEmojiCategories,
    super.key,
  });

  final List<EmojiCategory> emojiCategories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var flatIndex = 0;

    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add emoji',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                key: const Key('updates_media_emoji_category_list'),
                children: [
                  for (final category in emojiCategories) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        category.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    // A fixed-column grid (not an organic Wrap) so every
                    // row lines up identically and the last column never
                    // leaves an inconsistent gap on the right -- the exact
                    // "layout issue on right side" a Wrap risks once the
                    // available width doesn't divide evenly into whole
                    // items.
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: category.emoji.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, i) {
                        final emoji = category.emoji[i];
                        final index = flatIndex++;
                        return InkWell(
                          key: Key('updates_media_emoji_option_$index'),
                          onTap: () => Navigator.of(context).pop(emoji),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.52),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: usesTwemoji(theme.platform)
                                  ? Semantics(
                                      label: emoji,
                                      child: ExcludeSemantics(
                                        child: Twemoji(
                                          emoji: emoji,
                                          width: 26,
                                          height: 26,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      emoji,
                                      style: emojiPreviewTextStyle(
                                        context,
                                        fontSize: 26,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
