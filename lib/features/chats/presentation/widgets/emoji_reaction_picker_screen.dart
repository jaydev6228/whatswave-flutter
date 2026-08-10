import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// A full-screen emoji keyboard (search, recent, categories, grid) for the
/// reaction tray's "+" button -- replaces the earlier bare-TextField bottom
/// sheet, which only worked by handing off to the OS keyboard's own emoji
/// panel instead of showing a real picker.
class EmojiReactionPickerScreen extends StatelessWidget {
  const EmojiReactionPickerScreen({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const EmojiReactionPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;

    return Scaffold(
      key: const Key('emoji_reaction_picker_screen'),
      appBar: AppBar(
        title: const Text(
          'React with',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: EmojiPicker(
          key: const Key('emoji_reaction_picker_grid'),
          onEmojiSelected: (category, emoji) =>
              Navigator.of(context).pop(emoji.emoji),
          config: Config(
            height: null,
            emojiViewConfig: EmojiViewConfig(
              columns: 8,
              backgroundColor: surface,
              emojiSizeMax: 30,
              recentsLimit: 28,
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: surface,
              indicatorColor: theme.colorScheme.primary,
              iconColor: onSurface.withValues(alpha: 0.5),
              iconColorSelected: theme.colorScheme.primary,
              backspaceColor: theme.colorScheme.primary,
              dividerColor: surfaceVariant,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: surface,
              buttonIconColor: onSurface.withValues(alpha: 0.6),
            ),
            bottomActionBarConfig: BottomActionBarConfig(
              showBackspaceButton: false,
              backgroundColor: surface,
              buttonColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
