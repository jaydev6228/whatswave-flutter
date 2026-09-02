import 'package:flutter/material.dart';

/// The app's single search-field look -- filled background, 14/9 content
/// padding, a 40x40 leading icon slot, rounded borders that tint on focus,
/// and a clear ("x") button that appears once there's text. Several screens
/// (chats, archived chats, communities, new chat, new group, community
/// invite) each hand-rolled a slightly different version of this, which is
/// why search fields didn't all look the same height/style across the app.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.focusNode,
    this.onTapOutside,
    this.textInputAction = TextInputAction.search,
    this.fieldKey,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  /// Called after the clear button empties [controller] (and after
  /// [onChanged] fires with an empty string) -- for callers that need to
  /// react further, e.g. dismissing focus.
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final void Function(PointerDownEvent)? onTapOutside;
  final TextInputAction textInputAction;

  /// Key for the underlying [TextField] itself (widget tests target this).
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          textInputAction: textInputAction,
          onTapOutside: onTapOutside,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            filled: true,
            // Same translucent fill and hairline the glass capsules use, so
            // the field reads as one of them rather than a stock Material
            // input sitting among them.
            fillColor: theme.colorScheme.onSurface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.08 : 0.05,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 9,
            ),
            prefixIcon: const Icon(Icons.search_rounded),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            // Capsule, like every other control in this language.
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(999)),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.16),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.68),
              ),
            ),
            suffixIcon: controller.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                      onClear?.call();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );
      },
    );
  }
}
