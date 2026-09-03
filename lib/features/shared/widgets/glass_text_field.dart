import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// Borderless field decoration for inputs that already sit on glass.
InputDecoration glassFieldDecoration({
  String? hintText,
  TextAlign textAlign = TextAlign.start,
  EdgeInsetsGeometry? contentPadding,
  String counterText = '',
}) {
  return InputDecoration(
    filled: false,
    hintText: hintText,
    counterText: counterText,
    contentPadding: contentPadding,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}

/// A [TextField] on the app's glass surface instead of the theme's opaque
/// filled capsule with a heavy focus ring. Theme-aware [LiquidGlassSurface]
/// on purpose -- the fixed-dark StatusChrome* family is for controls floating
/// over media, and would render white-on-white in light mode.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    required this.fieldKey,
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.maxLength,
    this.onSubmitted,
    this.style,
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String hintText;
  final int maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      blurred: false,
      showShadow: false,
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        minLines: minLines,
        textInputAction: textInputAction,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        textAlign: textAlign,
        maxLength: maxLength,
        onSubmitted: onSubmitted,
        style: style,
        decoration: glassFieldDecoration(hintText: hintText),
      ),
    );
  }
}

/// Sheet action on the app's neutral glass -- not a green filled slab.
class GlassPrimaryButton extends StatelessWidget {
  const GlassPrimaryButton({
    required this.actionKey,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = false,
    this.isLoading = false,
    super.key,
  });

  final Key actionKey;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(999));

    final button = LiquidGlassSurface(
      blurred: false,
      showShadow: false,
      borderRadius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: actionKey,
          onTap: isLoading ? null : onPressed,
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: _buttonChild(theme),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  Widget _buttonChild(ThemeData theme) {
    if (isLoading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    final labelWidget = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );

    if (icon == null) {
      return labelWidget;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        const SizedBox(width: 8),
        Flexible(child: labelWidget),
      ],
    );
  }
}

/// Compact glass capsule for inline row actions (Add, Added, Pending, etc.).
class GlassCompactActionButton extends StatelessWidget {
  const GlassCompactActionButton({
    required this.actionKey,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.muted = false,
    super.key,
  });

  final Key actionKey;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(999));
    final enabled = onPressed != null && !isLoading && !muted;
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.48);

    return LiquidGlassSurface(
      blurred: false,
      showShadow: false,
      borderRadius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: actionKey,
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
