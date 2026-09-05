import 'package:flutter/material.dart';

/// Name + animated dots for a chat list row while someone else is typing.
class TypingStatusLine extends StatelessWidget {
  const TypingStatusLine({
    required this.threadId,
    required this.label,
    required this.color,
    required this.animate,
    this.isDirectChat = false,
    this.style,
    super.key,
  });

  final String threadId;
  final String label;
  final Color color;
  final bool animate;
  final bool isDirectChat;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = label.trim().isEmpty ? 'Typing' : label.trim();
    final semanticsLabel =
        isDirectChat ? 'typing' : '$effectiveLabel is typing';
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Flexible(
              child: Text(
                effectiveLabel,
                key: Key('chat_typing_name_$threadId'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 6),
            TypingDotsIndicator(
              key: Key('chat_typing_indicator_$threadId'),
              threadId: threadId,
              color: color,
              animate: animate,
            ),
          ],
        ),
      ),
    );
  }
}

class TypingDotsIndicator extends StatefulWidget {
  const TypingDotsIndicator({
    required this.threadId,
    required this.color,
    required this.animate,
    this.dotSize = 5,
    super.key,
  });

  final String threadId;
  final Color color;
  final bool animate;
  final double dotSize;

  @override
  State<TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.value = 0.32;
    }
  }

  @override
  void didUpdateWidget(covariant TypingDotsIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) {
      return;
    }
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0.32;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityForDot(int index) {
    final progress = (_controller.value + (index * 0.18)) % 1.0;
    final triangle = 1.0 - ((progress * 2) - 1).abs();
    return 0.24 + (triangle * 0.76);
  }

  double _scaleForDot(int index) {
    final progress = (_controller.value + (index * 0.18)) % 1.0;
    final triangle = 1.0 - ((progress * 2) - 1).abs();
    return 0.82 + (triangle * 0.24);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Transform.scale(
                scale: _scaleForDot(index),
                child: Opacity(
                  key: Key('chat_typing_dot_${widget.threadId}_$index'),
                  opacity: _opacityForDot(index),
                  child: Container(
                    width: widget.dotSize,
                    height: widget.dotSize,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Incoming-style bubble with animated dots at the bottom of a conversation.
class ConversationTypingBubble extends StatelessWidget {
  const ConversationTypingBubble({
    required this.threadId,
    required this.isGroup,
    required this.senderLabel,
    required this.semanticsLabel,
    required this.accentColor,
    super.key,
  });

  final String threadId;
  final bool isGroup;
  final String senderLabel;
  final String semanticsLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (semanticsLabel.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final bubbleColor = theme.colorScheme.surfaceContainerLow;
    final dotColor = theme.colorScheme.onSurface.withValues(alpha: 0.42);

    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isGroup && senderLabel.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    senderLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              DecoratedBox(
                key: Key('conversation_typing_$threadId'),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(5),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: TypingDotsIndicator(
                    key: Key('conversation_typing_dots_$threadId'),
                    threadId: threadId,
                    color: dotColor,
                    animate: true,
                    dotSize: 7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
