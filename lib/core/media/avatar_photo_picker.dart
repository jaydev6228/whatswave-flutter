import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/shared/presentation/avatar_crop_screen.dart';
import '../../features/shared/widgets/liquid_glass.dart';

enum AvatarPhotoSheetAction { choose, remove }

/// Test hook -- widget tests inject this to skip the crop screen.
Future<File?> Function(BuildContext context, File source)? avatarCropOverride;

/// WhatsApp-style sheet for changing or removing a circular profile/group
/// photo -- one place for choose/remove instead of separate overlay buttons.
/// The choose/remove bubble for a circular profile or group photo.
///
/// The same liquid-glass bubble the status "+" and the chat attachment
/// menu use (see showStatusComposeChoice), rather than a modal bottom
/// sheet -- a two-item choice anchored to the button that opened it, not a
/// panel sliding up over the whole screen.
///
/// [anchorContext] must be scoped to the tapped avatar itself (wrap it in a
/// Builder), or the bubble anchors to the whole screen instead of the
/// control the user touched.
Future<AvatarPhotoSheetAction?> showAvatarPhotoOptionsSheet(
  BuildContext anchorContext, {
  required bool canRemove,
}) {
  return showLiquidGlassBubbleMenu<AvatarPhotoSheetAction>(
    anchorContext: anchorContext,
    // The avatar sits near the top of every screen that offers this.
    openBelow: true,
    itemBuilder: (sheetContext) => [
      LiquidGlassBubbleItem(
        key: const Key('avatar_photo_choose_button'),
        icon: Icons.photo_library_outlined,
        label: 'Choose photo',
        onTap: () =>
            Navigator.of(sheetContext).pop(AvatarPhotoSheetAction.choose),
      ),
      if (canRemove)
        LiquidGlassBubbleItem(
          key: const Key('avatar_photo_remove_button'),
          icon: Icons.delete_outline_rounded,
          label: 'Remove photo',
          color: Theme.of(sheetContext).colorScheme.error,
          onTap: () =>
              Navigator.of(sheetContext).pop(AvatarPhotoSheetAction.remove),
        ),
    ],
  );
}

/// Picks from gallery, runs the square crop/adjust step, and returns the
/// cropped file ready to upload.
Future<File?> pickAndCropAvatarPhoto(BuildContext context) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 92,
  );
  if (picked == null || !context.mounted) {
    return null;
  }

  final source = File(picked.path);
  final crop = avatarCropOverride;
  if (crop != null) {
    return crop(context, source);
  }

  return Navigator.of(context).push<File?>(
    MaterialPageRoute(
      builder: (_) => AvatarCropScreen(sourceFile: source),
    ),
  );
}

/// Small camera badge shown only while editing -- no separate delete badge.
class AvatarCameraBadge extends StatelessWidget {
  const AvatarCameraBadge({
    this.isBusy = false,
    super.key,
  });

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      right: -2,
      bottom: -2,
      child: Material(
        color: theme.colorScheme.primary,
        shape: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.surface,
              width: 2,
            ),
          ),
          child: SizedBox(
            width: 16,
            height: 16,
            child: isBusy
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  )
                : Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: theme.colorScheme.onPrimary,
                  ),
          ),
        ),
      ),
    );
  }
}
