import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/status_story.dart';
import '../../shared/widgets/error_dialog.dart';
import '../application/updates_controller.dart';
import 'media_status_composer_screen.dart';
import 'text_status_composer_screen.dart';

enum _StatusComposeChoice { text, media }

/// A compact "Text status" / "Photo or video" choice sheet -- the shared
/// entry point for starting a new status wherever there's only room for one
/// "+" affordance (e.g. ChatsScreen's status strip).
Future<void> showStatusComposeChoice(
  BuildContext context,
  UpdatesController controller,
  ImagePicker imagePicker,
) async {
  final choice = await showModalBottomSheet<_StatusComposeChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('status_compose_choice_text'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Text status'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_StatusComposeChoice.text),
            ),
            ListTile(
              key: const Key('status_compose_choice_media'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Photo or video'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_StatusComposeChoice.media),
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || choice == null) {
    return;
  }

  switch (choice) {
    case _StatusComposeChoice.text:
      await openTextStatusComposer(context, controller);
    case _StatusComposeChoice.media:
      await pickStatusMedia(context, controller, imagePicker);
  }
}

Future<void> openTextStatusComposer(
  BuildContext context,
  UpdatesController controller,
) async {
  final draft = await Navigator.of(context).push<TextStatusComposerDraft>(
    MaterialPageRoute<TextStatusComposerDraft>(
      builder: (_) => const TextStatusComposerScreen(),
      fullscreenDialog: true,
    ),
  );
  if (!context.mounted || draft == null) {
    return;
  }

  final didCreate = await controller.createStatus(
    type: StatusStoryType.text,
    caption: draft.caption,
    textStyle: draft.textStyle,
  );
  if (!context.mounted || !didCreate) {
    return;
  }
}

Future<void> pickStatusMedia(
  BuildContext context,
  UpdatesController controller,
  ImagePicker imagePicker,
) async {
  if (controller.isComposingStatus) {
    return;
  }

  try {
    final pickedMedia =
        await imagePicker.pickMedia(requestFullMetadata: false);
    if (!context.mounted || pickedMedia == null) {
      return;
    }

    final statusType = _statusTypeForPickedMedia(pickedMedia);
    if (statusType == null) {
      await _showStatusError(
        context,
        'That media type is not supported for status updates yet.',
      );
      return;
    }

    final initialSourceSizeHint = await _resolveInitialStatusMediaSize(
      pickedMedia,
      statusType,
    );
    if (!context.mounted) {
      return;
    }

    final draft = await Navigator.of(context).push<MediaStatusComposerDraft>(
      MaterialPageRoute<MediaStatusComposerDraft>(
        builder: (_) => MediaStatusComposerScreen(
          type: statusType,
          localMediaPath: pickedMedia.path,
          initialSourceSizeHint: initialSourceSizeHint,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!context.mounted || draft == null) {
      return;
    }

    final didCreate = await controller.createStatus(
      type: statusType,
      caption: draft.caption,
      localMediaPath: pickedMedia.path,
      textStyle: draft.textStyle,
      mediaTransform: draft.mediaTransform,
      overlayItems: draft.overlayItems,
      emoji: draft.emoji,
      stickers: draft.stickers,
      musicTrack: draft.musicTrack,
      durationMillis: draft.durationMillis,
    );
    if (!context.mounted || !didCreate) {
      return;
    }
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    await _showStatusError(
      context,
      'We could not open your gallery right now. Please try again.',
    );
  }
}

Future<Size?> _resolveInitialStatusMediaSize(
  XFile pickedMedia,
  StatusStoryType statusType,
) async {
  if (statusType != StatusStoryType.photo) {
    return null;
  }

  try {
    final bytes = await File(pickedMedia.path).readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

StatusStoryType? _statusTypeForPickedMedia(XFile media) {
  final normalizedMimeType = media.mimeType?.trim().toLowerCase();
  if (normalizedMimeType?.startsWith('image/') == true) {
    return StatusStoryType.photo;
  }
  if (normalizedMimeType?.startsWith('video/') == true) {
    return StatusStoryType.video;
  }

  final lowerPath = media.path.trim().toLowerCase();
  const photoExtensions = <String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.heic',
    '.heif',
    '.gif',
    '.webp',
  ];
  for (final extension in photoExtensions) {
    if (lowerPath.endsWith(extension)) {
      return StatusStoryType.photo;
    }
  }

  const videoExtensions = <String>[
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.mkv',
    '.webm',
    '.3gp',
  ];
  for (final extension in videoExtensions) {
    if (lowerPath.endsWith(extension)) {
      return StatusStoryType.video;
    }
  }

  return null;
}

Future<void> _showStatusError(BuildContext context, String message) {
  return showErrorDialog(context, message);
}
