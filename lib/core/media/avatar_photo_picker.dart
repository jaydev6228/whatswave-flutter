import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/shared/presentation/avatar_crop_screen.dart';

enum AvatarPhotoSheetAction { choose, remove }

/// Test hook -- widget tests inject this to skip the crop screen.
Future<File?> Function(BuildContext context, File source)? avatarCropOverride;

/// WhatsApp-style sheet for changing or removing a circular profile/group
/// photo -- one place for choose/remove instead of separate overlay buttons.
Future<AvatarPhotoSheetAction?> showAvatarPhotoOptionsSheet(
  BuildContext context, {
  required bool canRemove,
}) {
  return showModalBottomSheet<AvatarPhotoSheetAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('avatar_photo_choose_button'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(AvatarPhotoSheetAction.choose),
            ),
            if (canRemove)
              ListTile(
                key: const Key('avatar_photo_remove_button'),
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(AvatarPhotoSheetAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
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
