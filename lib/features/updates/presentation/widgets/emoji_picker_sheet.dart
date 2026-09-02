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
/// The emoji grid both status composers show, as list children.
///
/// One source rather than two near-identical copies: the media composer's
/// stickers sheet and the text composer's emoji sheet had the same sixty
/// lines of grid each, so a change to one silently left the other behind.
///
/// Returns children to spread into the caller's ListView rather than a
/// single Column widget. A Column would be one list child, so the whole
/// emoji set would build and lay out at once instead of the list inflating
/// only what is on screen.
List<Widget> buildStatusEmojiCategories(
  BuildContext context, {
  List<EmojiCategory> categories = kStatusEmojiCategories,
  int startIndex = 0,
}) {
  final theme = Theme.of(context);
  var flatIndex = startIndex;

  return [
    for (final category in categories) ...[
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          category.label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
      // A fixed-column grid (not an organic Wrap) so every row lines up
      // identically and the last column never leaves an inconsistent gap
      // on the right -- the exact "layout issue on right side" a Wrap
      // risks once the available width doesn't divide evenly into whole
      // items.
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: category.emoji.length,
        // No tile behind each glyph. The platform's own emoji are already
        // full-colour artwork, and boxing each one in a rounded square read
        // as chrome competing with the picture it frames -- it also forced a
        // wider cell, so fewer fitted per row.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, i) {
          final emoji = category.emoji[i];
          final index = flatIndex++;
          return InkWell(
            key: Key('updates_media_emoji_option_$index'),
            onTap: () => Navigator.of(context).pop(emoji),
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: usesTwemoji(theme.platform)
                  ? Semantics(
                      label: emoji,
                      child: ExcludeSemantics(
                        child: Twemoji(emoji: emoji, width: 30, height: 30),
                      ),
                    )
                  : Text(
                      emoji,
                      style: emojiPreviewTextStyle(context, fontSize: 30),
                    ),
            ),
          );
        },
      ),
      const SizedBox(height: 18),
    ],
  ];
}

class EmojiPickerSheet extends StatelessWidget {
  const EmojiPickerSheet({
    this.emojiCategories = kStatusEmojiCategories,
    super.key,
  });

  final List<EmojiCategory> emojiCategories;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        // No title: the button that opened this already said what it is.
        child: ListView(
          key: const Key('updates_media_emoji_category_list'),
          children: buildStatusEmojiCategories(
            context,
            categories: emojiCategories,
          ),
        ),
      ),
    );
  }
}
