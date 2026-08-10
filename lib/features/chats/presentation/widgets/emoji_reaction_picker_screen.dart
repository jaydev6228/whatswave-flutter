import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// A near-full-height emoji keyboard (search, recent, categories, grid) for
/// the reaction tray's "+" button -- presented as a modal sheet over the
/// current screen (not a separate pushed route) so it reads as "picking an
/// emoji here" rather than "leaving the conversation". Tapping any emoji
/// reacts and dismisses immediately, the same one-tap flow as the 6 quick
/// react emoji.
class EmojiReactionPickerSheet extends StatelessWidget {
  const EmojiReactionPickerSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Deliberately not useSafeArea:true -- the sheet's own background
      // paints under the home indicator (this app's edge-to-edge
      // convention, see _ComposerBar's bottom padding in
      // conversation_screen.dart), while the picker's own bottom padding
      // below keeps the search/category row clear of that inset instead.
      builder: (_) => const EmojiReactionPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      key: const Key('emoji_reaction_picker_screen'),
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'React with',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Padding(
              // Keeps the search/category action row clear of the home
              // indicator without reserving that space as dead white area
              // above it -- the sheet's background already extends to the
              // physical bottom edge.
              padding: EdgeInsets.only(bottom: bottomInset),
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
          ),
        ],
      ),
    );
  }
}
