import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../shared/widgets/liquid_glass.dart';

/// The one background every floating control in the status feature sits on
/// -- both composers, the trim strip, and the sheets.
///
/// Taken from the tool capsule at the top of the media composer, which is
/// the look the rest was meant to match: a flat translucent black fill with
/// a hairline light border, and deliberately **no** backdrop blur or
/// shadow. Reaching for a blurred glass surface instead is what made the
/// caption field and the mute button read as different materials from the
/// capsule right above them.
///
/// Fixed dark regardless of app theme -- these float over the story, not
/// over the system surface, so they must stay legible whatever the media
/// and whatever theme the rest of the app is in.
class StatusChromeSurface extends StatelessWidget {
  const StatusChromeSurface({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.padding,
    this.showBorder = true,
    this.blurred = false,
    super.key,
  });

  static const Color fill = Color(0x38000000); // black @ 0.22
  static const Color border = Color(0x14FFFFFF); // white @ 0.08

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool showBorder;

  /// Blurs whatever is behind this surface.
  ///
  /// Off by default -- most composer chrome sits over a scrim, where a
  /// blur only muddies it. On for controls that sit directly on the media
  /// with nothing between them and it, like the crop tool's, which were
  /// hard to pick out against a busy frame.
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(color: showBorder ? border : Colors.transparent),
      ),
      child: child,
    );
    if (!blurred) {
      return decorated;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: decorated,
      ),
    );
  }
}

/// A square icon button on the shared composer background.
///
/// Square rather than a circle so it reads as part of the same family as
/// the capsule and the caption field, which are rounded rectangles.
class StatusChromeButton extends StatelessWidget {
  const StatusChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.bare = false,
    this.blurred = false,
    this.busy = false,
    this.size = defaultSize,
    super.key,
  });

  /// Composer chrome: full 44pt tap target
  /// (docs/ui_layout_guidelines.md rule 7).
  static const double defaultSize = 44;

  /// Story viewer chrome: the smaller standalone buttons that float over a
  /// posted story, where the media is the subject and the controls should
  /// stay out of its way.
  static const double compactSize = 32;

  /// Edge length of the button. See [defaultSize] and [compactSize].
  final double size;

  final String tooltip;
  final IconData icon;

  /// Null disables the button.
  final VoidCallback? onTap;

  /// Blurs behind the button -- see [StatusChromeSurface.blurred].
  final bool blurred;

  /// Drops this button's own background, for use inside a
  /// [StatusChromeButtonGroup] which supplies one for the whole row.
  final bool bare;

  /// Swaps the glyph for a spinner and ignores taps, for an action already
  /// running -- deleting a status, say. Keeps the button's footprint
  /// identical so the row it sits in doesn't reflow mid-action.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    final button = Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: radius,
        // No spreading ink. This chrome floats directly on the media, so a
        // ripple washes across the picture -- and the buttons that change
        // screen (crop's Done, the viewer's close) leave one running as the
        // screen moves out from under it. A contained highlight gives the
        // same acknowledgement without painting over the photo.
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.white.withValues(alpha: 0.12),
        child: SizedBox(
          width: size,
          height: size,
          child: busy
              ? Center(
                  child: SizedBox(
                    width: size * 0.36,
                    height: size * 0.36,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: size * 0.45,
                  color: onTap == null
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.white,
                ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: bare
          ? button
          : StatusChromeSurface(
              borderRadius: radius,
              blurred: blurred,
              child: button,
            ),
    );
  }
}

/// Two or more chrome buttons sharing one capsule, the way the tool
/// toolbar does. Adjacent buttons each carrying their own background read
/// as scattered controls rather than one group.
class StatusChromeButtonGroup extends StatelessWidget {
  const StatusChromeButtonGroup({
    required this.children,
    this.blurred = false,
    super.key,
  });

  final List<Widget> children;

  /// Blurs behind the capsule -- see [StatusChromeSurface.blurred].
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    return StatusChromeSurface(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      blurred: blurred,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The send button: the same background as everything else, with the
/// primary-coloured glyph the chat composer's send button uses.
///
/// Blurred behind, like the caption field it sits next to -- a placed text
/// overlay can land right behind it, and the glyph has to stay findable.
class StatusChromeSendButton extends StatelessWidget {
  const StatusChromeSendButton({
    required this.actionKey,
    required this.onTap,
    this.busy = false,
    this.tooltip = 'Share status',
    super.key,
  });

  final Key actionKey;

  /// Null disables the button.
  final VoidCallback? onTap;

  /// Swaps the icon for a spinner and ignores taps -- for a send that has
  /// real work to do first (baking a rotation, say) rather than one that
  /// pops immediately.
  final bool busy;

  /// What the button does, for screen readers and the tooltip.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(999));
    return Tooltip(
      message: tooltip,
      child: StatusChromeSurface(
        borderRadius: radius,
        blurred: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            key: actionKey,
            onTap: busy ? null : onTap,
            borderRadius: radius,
            // Same reasoning as StatusChromeButton above.
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.white.withValues(alpha: 0.12),
            child: SizedBox(
              width: 48,
              height: 48,
              child: busy
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.send_rounded,
                      size: 22,
                      color: onTap == null
                          ? theme.colorScheme.primary.withValues(alpha: 0.4)
                          : theme.colorScheme.primary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass caption capsule that pairs with [StatusChromeSendButton].
///
/// Shared by the status composer and the chat media send preview: the two
/// are the same "review this before it goes out" bar, and they looked like
/// two different apps when one was a filled grey field next to a solid
/// green circle.
class StatusChromeCaptionField extends StatelessWidget {
  const StatusChromeCaptionField({
    required this.fieldKey,
    required this.controller,
    this.hintText = 'Add a caption...',
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    // The capsule's exact fill and border, plus a backdrop blur.
    //
    // A placed text overlay can be huge and land anywhere, including right
    // behind this row -- at which point the hint and the caret were
    // competing with headline-sized text showing through. Blurring what is
    // behind separates them without changing the material: same colour,
    // same border, still translucent.
    return StatusChromeSurface(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      blurred: true,
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: 3,
        minLines: 1,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          // The app theme fills text fields, which painted an opaque slab
          // inside the glass and left the caption looking like a cut-out
          // bar rather than something laid over the story.
          filled: false,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          // Every state spelled out, not just `border`: the app theme
          // supplies enabledBorder/focusedBorder, which drew a second
          // outline inside the surface so the caption's edge never matched
          // the send button's.
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

/// The shell the status feature's modal sheets sit in.
///
/// The emoji/sticker and music sheets used a flat `colorScheme.surface`,
/// which read as a plain app panel dropped on top of the story rather than
/// part of its chrome. This gives them the app's own glass instead --
/// blurred, so the media stays visible behind, and theme-following so the
/// list text keeps its contrast in both light and dark.
class StatusChromeSheet extends StatelessWidget {
  const StatusChromeSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      blurSigma: 30,
      // Heavier tint than the floating chrome: a long scrolling list has to
      // stay readable, not just legible for a moment.
      tintOpacityDark: 0.86,
      tintOpacityLight: 0.9,
      showShadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Our own handle, drawn inside the glass. Flutter's
          // `showDragHandle` renders it in the sheet's own area, which is
          // transparent here, so it floated above the sheet instead of
          // sitting in it.
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}
