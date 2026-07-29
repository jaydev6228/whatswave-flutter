import 'package:flutter/material.dart';

class SearchPrompt extends StatelessWidget {
  const SearchPrompt({
    required this.hint,
    super.key,
  });

  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
