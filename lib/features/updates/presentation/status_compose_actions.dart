import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/status_story.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../application/updates_controller.dart';
import 'media_status_composer_screen.dart';
import 'text_status_composer_screen.dart';
import 'status_motion.dart';

enum _StatusComposeChoice { text, media }

/// A compact "Text status" / "Photo or video" choice bubble -- the shared
/// entry point for starting a new status wherever there's only room for one
/// "+" affordance (e.g. ChatsScreen's status strip). [anchorContext] should
/// be scoped to the tapped "+" button itself (e.g. via a [Builder] wrapping
/// just that button) so the bubble opens right below it, matching the
/// app's own liquid-glass bubble chrome instead of a generic modal sheet.
Future<void> showStatusComposeChoice(
  BuildContext anchorContext,
  UpdatesController controller,
  ImagePicker imagePicker,
) async {
  final choice = await showLiquidGlassBubbleMenu<_StatusComposeChoice>(
    anchorContext: anchorContext,
    openBelow: true,
    itemBuilder: (sheetContext) => [
      LiquidGlassBubbleItem(
        key: const Key('status_compose_choice_text'),
        icon: Icons.edit_outlined,
        label: 'Text status',
        onTap: () =>
            Navigator.of(sheetContext).pop(_StatusComposeChoice.text),
      ),
      LiquidGlassBubbleItem(
        key: const Key('status_compose_choice_media'),
        icon: Icons.photo_camera_outlined,
        label: 'Photo or video',
        onTap: () =>
            Navigator.of(sheetContext).pop(_StatusComposeChoice.media),
      ),
    ],
  );
  if (!anchorContext.mounted || choice == null) {
    return;
  }
  final context = anchorContext;

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
    statusSheetRoute<TextStatusComposerDraft>(
      name: 'status/compose/text',
      builder: (_) => const TextStatusComposerScreen(),
    ),
  );
  if (!context.mounted || draft == null) {
    return;
  }

  final didCreate = await controller.createStatus(
    type: StatusStoryType.text,
    caption: draft.caption,
    textStyle: draft.textStyle,
    overlayItems: draft.overlayItems,
  );
  if (!context.mounted) {
    return;
  }
  if (!didCreate) {
    await _showStatusError(
      context,
      controller.errorMessage ?? 'We could not post that status right now.',
    );
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
    final pickedMedia = await imagePicker.pickMedia(requestFullMetadata: false);
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
      statusSheetRoute<MediaStatusComposerDraft>(
        name: 'status/compose/media',
        builder: (_) => MediaStatusComposerScreen(
          type: statusType,
          localMediaPath: pickedMedia.path,
          initialSourceSizeHint: initialSourceSizeHint,
          loadMusicTracks: controller.fetchMusicTracks,
        ),
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
      trimStartMillis: draft.trimStartMillis,
      drawingStrokes: draft.drawingStrokes,
    );
    if (!context.mounted) {
      return;
    }
    if (!didCreate) {
      // Previously silent -- a failed post (e.g. a slow/flaky video
      // upload) left the user with no feedback at all: no error, and
      // nothing in the status list either, even though the media itself
      // could still land in Firebase Storage first. Matches the error
      // dialog UpdatesScreen's own composer entry point already shows for
      // the same failure (see updates_screen.dart).
      await _showStatusError(
        context,
        controller.errorMessage ?? 'We could not post that status right now.',
      );
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
