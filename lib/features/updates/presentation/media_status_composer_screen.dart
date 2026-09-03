import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../data/status_music_repository.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/status_story_media_surface.dart';
import 'widgets/video_trim_scrubber.dart';
import '../../shared/widgets/status_motion.dart';
import 'widgets/status_text_editing_tools.dart';
import 'status_system_chrome.dart';
import 'widgets/draw_tools.dart';
import 'widgets/status_chrome.dart';
import 'widgets/rotation_dial.dart';
import 'widgets/overlay_delete_target.dart';

class MediaStatusComposerDraft {
  const MediaStatusComposerDraft({
    required this.caption,
    required this.textStyle,
    required this.mediaTransform,
    required this.overlayItems,
    required this.emoji,
    required this.stickers,
    required this.musicTrack,
    required this.durationMillis,
    this.trimStartMillis = 0,
    this.drawingStrokes = const <StatusDrawingStroke>[],
  });

  final String caption;
  final StatusTextStyle textStyle;
  final StatusMediaTransform mediaTransform;
  final List<StatusMediaOverlayItem> overlayItems;
  final String? emoji;
  final List<String> stickers;
  final StatusMusicTrack? musicTrack;
  final int durationMillis;
  final int trimStartMillis;
  final List<StatusDrawingStroke> drawingStrokes;
}

class _StickerPreset {
  const _StickerPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.accentColorValue,
    required this.secondaryColorValue,
  });

  final String id;
  final String label;
  final IconData icon;
  final int accentColorValue;
  final int secondaryColorValue;
}

class _MusicBannerStyleOption {
  const _MusicBannerStyleOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Which corner of the crop window a drag handle controls -- dragging one
/// resizes the window from that corner while the opposite corner stays
/// fixed, matching WhatsApp's own free-form crop handles.
enum _CropCorner { topLeft, topRight, bottomLeft, bottomRight }

class _CropAspectOption {
  const _CropAspectOption({
    required this.label,
    required this.ratio,
    this.isOriginal = false,
  });

  final String label;

  /// Null means no fixed shape -- fills the available space (isOriginal
  /// distinguishes this from "Original", which is also unconstrained until
  /// resolved but should track the source media's own ratio specifically).
  final double? ratio;

  /// True only for "Original" -- resolves to the source media's own
  /// (rotation-adjusted) aspect ratio rather than truly clearing the
  /// constraint, which is what "Fit to screen" (ratio: null, isOriginal:
  /// false) does instead.
  final bool isOriginal;
}

// Just enough inset so an overlay's own footprint never pokes past the
// frame edge -- not a reserved "keep away from the chrome" gutter. WhatsApp
// lets text sit anywhere on the photo, including behind the floating top
// bar and bottom tray (both are translucent), so this no longer carves out
// a large no-go zone around them.
const EdgeInsets _kComposerOverlayReservedPadding = EdgeInsets.all(10);

Rect _composerOverlaySafeRectForFrame(Size frameSize) {
  final maxHorizontalInset = math.max((frameSize.width - 132) / 2, 0.0);
  final maxVerticalInset = math.max((frameSize.height - 180) / 2, 0.0);

  final left = _kComposerOverlayReservedPadding.left
      .clamp(0.0, maxHorizontalInset)
      .toDouble();
  final right = _kComposerOverlayReservedPadding.right
      .clamp(0.0, maxHorizontalInset)
      .toDouble();
  final top = _kComposerOverlayReservedPadding.top
      .clamp(0.0, maxVerticalInset)
      .toDouble();
  final bottom = _kComposerOverlayReservedPadding.bottom
      .clamp(0.0, maxVerticalInset)
      .toDouble();

  return Rect.fromLTWH(
    left,
    top,
    math.max(frameSize.width - left - right, 132.0).toDouble(),
    math.max(frameSize.height - top - bottom, 180.0).toDouble(),
  );
}

/// Seconds a video occupies, at millisecond precision.
///
/// Deliberately not `Duration.inSeconds`, which truncates: a 5.8s clip read
/// through `.inSeconds` becomes 5, and every trim rule built on it then stops
/// short of the clip's real end.
@visibleForTesting
double statusVideoSeconds(Duration? duration) =>
    (duration?.inMilliseconds ?? 0) / 1000;

/// Longest trim a video status allows: the whole clip, but never under the
/// 15s floor (so short clips still get a draggable range) nor over the 30s
/// status cap.
@visibleForTesting
double statusVideoMaxTrimSeconds(Duration? duration) =>
    statusVideoSeconds(duration).clamp(15, 30).toDouble();

/// Trim window a freshly picked video opens with: the entire clip, clamped to
/// the allowed range. Anything less leaves an unselected tail in the filmstrip
/// the moment the editor opens.
@visibleForTesting
double statusVideoDefaultTrimSeconds(
  Duration duration, {
  required double minSeconds,
}) =>
    statusVideoSeconds(
      duration,
    ).clamp(minSeconds, statusVideoMaxTrimSeconds(duration)).toDouble();

class MediaStatusComposerScreen extends StatefulWidget {
  const MediaStatusComposerScreen({
    required this.type,
    required this.localMediaPath,
    this.initialSourceSizeHint,
    this.loadMusicTracks,
    super.key,
  });

  final StatusStoryType type;
  final String localMediaPath;
  final Size? initialSourceSizeHint;

  /// Fetches the "Add music" catalog -- defaults to the bundled fallback
  /// list (same tracks as the real Firestore catalog, served instantly)
  /// so callers that don't wire a real loader, like widget tests, still
  /// get a working picker.
  final Future<List<StatusMusicTrack>> Function()? loadMusicTracks;

  @override
  State<MediaStatusComposerScreen> createState() =>
      _MediaStatusComposerScreenState();
}

class _MediaStatusComposerScreenState extends State<MediaStatusComposerScreen>
    with TickerProviderStateMixin {
  static const double _minOverlayPosition = 0.04;
  static const double _maxOverlayPosition = 0.96;

  // Room reserved above/below the media so the top controls (close/tools,
  // trim filmstrip) and bottom controls (caption/send, or a tool's own
  // floating buttons) never sit on top of it -- applied unconditionally,
  // in every mode, not just while cropping. Toggling it on/off only in
  // crop mode was what made the whole video visibly jump position the
  // moment you tapped the crop button.
  static const double _kMediaBottomInset = 132;
  double get _mediaTopInset => _isVideo ? 150 : 74;

  // Reserved space while actively editing a text overlay: clearance below
  // the top bar's alignment/decoration icons, and clearance above the
  // keyboard for the font-style row -- the centered editing card and the
  // color rail both fit inside the gap between these two.
  static const double _kTextEditTopClearance = 78;

  /// The tray's own inset from the bottom of the screen.
  static const double _kTextEditTrayInset = 14;

  // Everything the styling tray occupies: its inset from the bottom, both
  // rows, and a gap above. This used to assume a single 78pt row, from
  // when the tray had one -- once the size/weight row was added the colour
  // rail's lower stretch sat on top of the weight button and would not
  // take a drag there.
  static const double _kTextEditBottomRowHeight = _kTextEditTrayInset +
      kStatusTextSizeRowHeight +
      kStatusTextFontRowHeight +
      kStatusTextRowGap;

  static const List<_StickerPreset> _stickerPresets = <_StickerPreset>[
    _StickerPreset(
      id: 'live_badge',
      label: 'Live now',
      icon: Icons.graphic_eq_rounded,
      accentColorValue: 0xFFFF6740,
      secondaryColorValue: 0xFFFFC2A8,
    ),
    _StickerPreset(
      id: 'launch_card',
      label: 'New drop',
      icon: Icons.auto_awesome_rounded,
      accentColorValue: 0xFF25D366,
      secondaryColorValue: 0xFFDCFDEB,
    ),
    _StickerPreset(
      id: 'weekend_ticket',
      label: 'Weekend',
      icon: Icons.celebration_outlined,
      accentColorValue: 0xFFFFC857,
      secondaryColorValue: 0xFFFFF3CC,
    ),
    _StickerPreset(
      id: 'map_pin',
      label: 'Tokyo',
      icon: Icons.location_on_rounded,
      accentColorValue: 0xFF58A6FF,
      secondaryColorValue: 0xFFDCEBFF,
    ),
    _StickerPreset(
      id: 'night_stamp',
      label: 'After dark',
      icon: Icons.nights_stay_rounded,
      accentColorValue: 0xFF826AF9,
      secondaryColorValue: 0xFFE7E0FF,
    ),
    _StickerPreset(
      id: 'coffee_note',
      label: 'Coffee run',
      icon: Icons.coffee_rounded,
      accentColorValue: 0xFFC9804A,
      secondaryColorValue: 0xFFF8E5D5,
    ),
    _StickerPreset(
      id: 'camera_tag',
      label: 'No filter',
      icon: Icons.camera_alt_rounded,
      accentColorValue: 0xFF667781,
      secondaryColorValue: 0xFFE6EAEE,
    ),
    _StickerPreset(
      id: 'spotlight_chip',
      label: 'Spotlight',
      icon: Icons.bolt_rounded,
      accentColorValue: 0xFFFF7AB6,
      secondaryColorValue: 0xFFFFD8E8,
    ),
  ];

  static const List<_MusicBannerStyleOption> _musicBannerStyles =
      <_MusicBannerStyleOption>[
    _MusicBannerStyleOption(
      id: 'cover',
      label: 'Cover',
      icon: Icons.album_rounded,
    ),
    _MusicBannerStyleOption(
      id: 'pulse',
      label: 'Pulse',
      icon: Icons.graphic_eq_rounded,
    ),
    _MusicBannerStyleOption(
      id: 'mix',
      label: 'Mix',
      icon: Icons.tune_rounded,
    ),
    _MusicBannerStyleOption(
      id: 'minimal',
      label: 'Minimal',
      icon: Icons.music_note_rounded,
    ),
  ];

  static const StatusTextStyle _defaultTextOverlayStyle = StatusTextStyle(
    fontId: 'banner',
    backgroundId: 'midnight_drive',
    layout: StatusTextLayout.note,
    alignment: StatusTextAlignment.center,
    textColorValue: 0xFFFFFFFF,
    sizeScale: 0.98,
  );

  late double _durationSeconds;

  /// Where in the source video the trimmed range starts -- WhatsApp's "drag
  /// the slider at the top to trim the video". Always 0 for photos.
  double _trimStartSeconds = 0;
  StatusMediaTransform _mediaTransform = const StatusMediaTransform();
  final List<StatusMediaOverlayItem> _overlayItems = <StatusMediaOverlayItem>[];
  late final TextEditingController _inlineTextController;
  late final FocusNode _inlineTextFocusNode;
  final TextEditingController _captionController = TextEditingController();
  final GlobalKey _deleteTargetKey = GlobalKey();
  String? _selectedOverlayId;
  String? _editingTextOverlayId;
  StatusMusicTrack? _musicTrack;
  String? _previewingMusicTrackId;
  List<StatusMusicTrack>? _cachedMusicTracks;
  bool _showOverlayGuide = false;
  bool _isDeleteTargetActive = false;
  bool _isDraggingOverlay = false;
  Timer? _overlayGuideTimer;
  double? _originalMediaAspectRatio;
  bool _didSeedInitialMediaFrame = false;

  bool _isDrawMode = false;
  Color _drawColor = Colors.white;
  double _drawStrokeWidth = _drawStrokeWidths[1];
  bool _isEraserMode = false;
  final List<StatusDrawingStroke> _drawingStrokes = <StatusDrawingStroke>[];
  List<Offset>? _liveStrokePoints;

  static const List<double> _drawStrokeWidths = <double>[0.008, 0.014, 0.026];

  bool _isBlurMode = false;
  bool _isCropMode = false;

  /// "Original" and "Fit to screen" both clear the frame's aspect ratio to
  /// null (neither constrains the shape), so the ratio alone can't tell
  /// them apart afterward -- this is the one bit that disambiguates which
  /// of the two null-ratio options is actually selected, for the ratio
  /// button/bubble's own label and checkmark.
  bool _isFitToScreenCrop = false;

  /// User-controlled mute, independent of the automatic video-vs-music
  /// volume swap below -- either one silences the video's own audio.
  bool _isMuted = false;

  // Matches WhatsApp's own crop ratio list -- Original and Fit to screen
  // both start unconstrained but resolve differently (see
  // _CropAspectOption.isOriginal), then a full set of common portrait and
  // landscape ratios, same as the real app's list.
  static const List<_CropAspectOption> _cropAspectOptions = <_CropAspectOption>[
    _CropAspectOption(label: 'Original', ratio: null, isOriginal: true),
    _CropAspectOption(label: 'Fit to screen', ratio: null),
    _CropAspectOption(label: 'Square', ratio: 1),
    _CropAspectOption(label: '2:3', ratio: 2 / 3),
    _CropAspectOption(label: '3:4', ratio: 3 / 4),
    _CropAspectOption(label: '4:5', ratio: 4 / 5),
    _CropAspectOption(label: '5:7', ratio: 5 / 7),
    _CropAspectOption(label: '9:16', ratio: 9 / 16),
    _CropAspectOption(label: '3:2', ratio: 3 / 2),
    _CropAspectOption(label: '4:3', ratio: 4 / 3),
    _CropAspectOption(label: '5:4', ratio: 5 / 4),
    _CropAspectOption(label: '7:5', ratio: 7 / 5),
    _CropAspectOption(label: '16:9', ratio: 16 / 9),
  ];

  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;
  VideoPlayerController? _musicPreviewController;
  bool _isVideoPlaying = false;
  bool _isRewindingToTrimStart = false;

  /// Playback position, for the filmstrip's playhead.
  ///
  /// A notifier rather than setState: the controller ticks about ten times
  /// a second and only the strip needs to repaint -- rebuilding the whole
  /// composer at that rate would redraw the entire canvas so a 2pt line
  /// can move.
  final ValueNotifier<double?> _videoPosition = ValueNotifier<double?>(null);
  bool _wasPlayingBeforeTrimScrub = false;

  StatusMediaOverlayItem? _gestureAnchorOverlay;
  Offset? _gestureStartFocalPoint;
  StatusMediaTransform? _mediaGestureAnchorTransform;
  Offset? _mediaGestureStartFocalPoint;

  // Crop corner-handle resize -- separate from the whole-surface drag
  // gesture above, since a corner drag reshapes the window (changing
  // frameAspectRatio/scale) rather than just repositioning it.
  Rect? _cropResizeAnchorWindow;

  /// Eases the media back into the frame after a corner drag.
  ///
  /// Releasing a corner un-freezes the media, and the new selection then
  /// re-fits the fixed frame -- which, done in a single frame, snapped the
  /// picture into place. This runs that same re-fit as a movement.
  late final AnimationController _cropSettleController;
  RectTween? _cropSettleTween;

  /// Carries the crop tool in and out.
  ///
  /// 0 is the preview's framing, 1 is the tool's. Entering and leaving used
  /// to swap between the two in a single frame; driving the frame inset off
  /// this makes both a movement, matching the settle after a resize.
  late final AnimationController _cropModeController;
  late final Animation<double> _cropModeCurve;

  /// The canvas the crop handles were last laid out against, so the settle
  /// can work out where the selection is going without a BuildContext.
  Size? _lastCropCanvasSize;
  _CropCorner? _cropResizeActiveCorner;
  Offset? _cropResizeCurrentPoint;

  int _nextOverlaySeed = 0;

  bool get _isVideo => widget.type == StatusStoryType.video;
  bool get _isEditingTextOverlay => _editingTextOverlayId != null;
  // Dragging the crop window (to move it) or its corner handles (to
  // resize it) is only available inside the crop tool -- the media itself
  // never moves or scales on screen; only this window does, to choose
  // which part of the media ends up in the final crop, matching
  // WhatsApp's own crop tool.
  bool get _allowMediaTransformGestures =>
      _isCropMode &&
      !_isEditingTextOverlay &&
      _selectedOverlayId == null &&
      _gestureAnchorOverlay == null &&
      !_isDraggingOverlay &&
      !_isDrawMode;

  double get _minDurationSeconds => _isVideo ? 3 : 4;

  double get _maxDurationSeconds => _isVideo
      ? statusVideoMaxTrimSeconds(_videoController?.value.duration)
      : 15.0;

  bool _matchesAspectRatio(double? lhs, double? rhs) {
    if (lhs == null || rhs == null) {
      return false;
    }
    return (lhs - rhs).abs() < 0.02;
  }

  double? _normalizedAspectRatioFor(Size sourceSize) {
    if (!sourceSize.width.isFinite ||
        !sourceSize.height.isFinite ||
        sourceSize.width <= 0 ||
        sourceSize.height <= 0) {
      return null;
    }
    return (sourceSize.width / sourceSize.height).clamp(0.5, 2.2).toDouble();
  }

  int get _durationMillis => (_durationSeconds * 1000).round();
  int get _trimStartMillis => (_trimStartSeconds * 1000).round();

  double get _videoFullDurationSeconds =>
      statusVideoSeconds(_videoController?.value.duration);

  StatusMediaOverlayItem? get _selectedOverlay {
    final selectedId = _selectedOverlayId;
    if (selectedId == null) {
      return null;
    }
    for (final item in _overlayItems) {
      if (item.id == selectedId) {
        return item;
      }
    }
    return null;
  }

  StatusMediaOverlayItem? get _primaryTextOverlay {
    for (final item in _overlayItems.reversed) {
      if (item.type == StatusMediaOverlayType.text &&
          item.label.trim().isNotEmpty) {
        return item;
      }
    }
    return null;
  }

  StatusTextStyle get _summaryTextStyle =>
      _primaryTextOverlay?.textStyle ?? _defaultTextOverlayStyle;

  String? get _leadEmoji {
    for (final item in _overlayItems) {
      if (item.type == StatusMediaOverlayType.emoji &&
          item.label.trim().isNotEmpty) {
        return item.label.trim();
      }
    }
    return null;
  }

  List<String> get _stickerLabels => List<String>.unmodifiable(
        _overlayItems
            .where((item) => item.type == StatusMediaOverlayType.sticker)
            .map((item) => item.label.trim())
            .where((label) => label.isNotEmpty),
      );

  List<StatusMediaOverlayItem> get _shareableOverlayItems =>
      List<StatusMediaOverlayItem>.unmodifiable(
        _overlayItems.where(
          (item) => item.type != StatusMediaOverlayType.text
              ? item.label.trim().isNotEmpty
              : item.label.trim().isNotEmpty,
        ),
      );

  StatusTextStyle get _activeTextStyle =>
      (_selectedOverlay?.type == StatusMediaOverlayType.text
          ? _selectedOverlay?.textStyle
          : null) ??
      _defaultTextOverlayStyle;

  String get _selectedMusicStyleId {
    final selectedOverlay = _selectedOverlay;
    if (selectedOverlay?.type == StatusMediaOverlayType.music &&
        selectedOverlay?.variantId?.trim().isNotEmpty == true) {
      return selectedOverlay!.variantId!;
    }
    return _musicTrack?.bannerStyleId ?? _musicBannerStyles.first.id;
  }

  @override
  void initState() {
    super.initState();
    _cropModeController = AnimationController(
      vsync: this,
      // Shorter than the shared status timing. Entering and leaving move the
      // media across far more distance than the settle after a resize does,
      // and at 300ms that reads as sluggish next to it.
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    // Eased out going in and in coming back. Running the forward curve in
    // both directions left the tail of the exit crawling.
    _cropModeCurve = CurvedAnimation(
      parent: _cropModeController,
      curve: kStatusMotionCurve,
      reverseCurve: kStatusMotionReverseCurve,
    );
    _cropSettleController = AnimationController(
      vsync: this,
      duration: kStatusMotionDuration,
    )
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _cropSettleTween = null);
        }
      });
    _durationSeconds = widget.type == StatusStoryType.photo ? 7 : 12;
    _inlineTextController = TextEditingController()
      ..addListener(_handleInlineTextChanged);
    _inlineTextFocusNode = FocusNode();
    final initialSourceSizeHint = widget.initialSourceSizeHint;
    if (initialSourceSizeHint != null) {
      _adoptOriginalMediaFrameIfNeeded(
        initialSourceSizeHint,
        allowSetState: false,
      );
    }
    if (_isVideo) {
      _initializeVideoPreview();
    }
  }

  @override
  void dispose() {
    _cropSettleController.dispose();
    _cropModeController.dispose();
    _overlayGuideTimer?.cancel();
    _inlineTextController
      ..removeListener(_handleInlineTextChanged)
      ..dispose();
    _inlineTextFocusNode.dispose();
    _captionController.dispose();
    _videoPosition.dispose();
    _videoController?.dispose();
    _musicPreviewController?.dispose();
    super.dispose();
  }

  void _adoptOriginalMediaFrameIfNeeded(
    Size sourceSize, {
    bool allowSetState = true,
  }) {
    final aspectRatio = _normalizedAspectRatioFor(sourceSize);
    if (aspectRatio == null) {
      return;
    }

    final previousOriginalAspectRatio = _originalMediaAspectRatio;
    final shouldSeedFrame =
        !_didSeedInitialMediaFrame && _mediaTransform.frameAspectRatio == null;
    // A later, more accurate size (e.g. a video controller resolving its
    // real intrinsic size after the initial hint) re-seeds the frame too --
    // but only while nothing else has changed it since (there's no manual
    // crop UI anymore, so in practice that only ever means a rotation).
    final shouldKeepFrameSyncedToOriginal = !shouldSeedFrame &&
        previousOriginalAspectRatio != null &&
        _matchesAspectRatio(
          _mediaTransform.frameAspectRatio,
          previousOriginalAspectRatio,
        ) &&
        !_matchesAspectRatio(previousOriginalAspectRatio, aspectRatio);

    if (!shouldSeedFrame &&
        !shouldKeepFrameSyncedToOriginal &&
        _matchesAspectRatio(previousOriginalAspectRatio, aspectRatio)) {
      return;
    }

    void syncFrame() {
      _originalMediaAspectRatio = aspectRatio;
      if (shouldSeedFrame || shouldKeepFrameSyncedToOriginal) {
        _mediaTransform =
            _mediaTransform.copyWith(frameAspectRatio: aspectRatio);
        _didSeedInitialMediaFrame = true;
      }
    }

    if (allowSetState) {
      setState(syncFrame);
      return;
    }

    syncFrame();
  }

  void _resetMediaGestureState() {
    _mediaGestureAnchorTransform = null;
    _mediaGestureStartFocalPoint = null;
  }

  Future<void> _stopMusicPreview({bool clearPreviewingTrack = true}) async {
    final controller = _musicPreviewController;
    _musicPreviewController = null;
    if (controller != null) {
      try {
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (clearPreviewingTrack) {
        _previewingMusicTrackId = null;
      }
    });
  }

  Future<void> _playMusicPreview(
    StatusMusicTrack track, {
    bool toggleWhenSameTrack = false,
  }) async {
    final assetPath = track.previewAssetPath?.trim();
    if (assetPath == null || assetPath.isEmpty) {
      return;
    }

    if (toggleWhenSameTrack &&
        _previewingMusicTrackId == track.id &&
        _musicPreviewController != null) {
      final isPlaying = _musicPreviewController!.value.isPlaying;
      try {
        if (isPlaying) {
          await _musicPreviewController!.pause();
          if (mounted) {
            setState(() {
              _previewingMusicTrackId = null;
            });
          }
        } else {
          await _musicPreviewController!.play();
          if (mounted) {
            setState(() {
              _previewingMusicTrackId = track.id;
            });
          }
        }
      } catch (_) {}
      return;
    }

    await _stopMusicPreview(clearPreviewingTrack: false);

    final controller = videoPlayerControllerForAudioPath(assetPath);
    _musicPreviewController = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1);
      await controller.play();
      if (!mounted || _musicPreviewController != controller) {
        await controller.dispose();
        return;
      }
      setState(() {
        _previewingMusicTrackId = track.id;
      });
    } catch (_) {
      if (_musicPreviewController == controller) {
        _musicPreviewController = null;
      }
      await controller.dispose();
      if (mounted) {
        setState(() {
          _previewingMusicTrackId = null;
        });
      }
    }
  }

  Future<void> _initializeVideoPreview() async {
    final mediaFile = File(widget.localMediaPath);
    if (!mediaFile.existsSync()) {
      return;
    }

    final controller = VideoPlayerController.file(mediaFile);
    final initialization = controller.initialize();
    _videoController = controller;
    _videoInitialization = initialization;

    try {
      await initialization;
      // Looping is handled manually via _handleTrimLoopPosition below, so
      // the trimmed range (not the whole file) is what repeats -- WhatsApp's
      // real trim slider actually clips playback, it doesn't just annotate
      // a duration on top of the untouched full video.
      await controller.setLooping(false);
      controller.addListener(_handleTrimLoopPosition);
      // The preview should sound the same as the posted story does: the
      // video's own audio plays by default, muted only when a music track
      // is layered on top of it (matching status_story_viewer_screen.dart's
      // identical video-vs-music volume logic). Previously always muted
      // unconditionally, so a picked video had no sound until after
      // posting.
      await controller.setVolume(_effectiveVideoVolume);
      // Starts paused, showing the first frame with the play overlay ready
      // to tap -- matches WhatsApp's own video status editor, which never
      // autoplays either.
      _adoptOriginalMediaFrameIfNeeded(controller.value.size);

      if (controller.value.duration > Duration.zero) {
        _durationSeconds = statusVideoDefaultTrimSeconds(
          controller.value.duration,
          minSeconds: _minDurationSeconds,
        );
      }

      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  /// Keeps preview playback inside the trimmed range -- `video_player` has
  /// no native "play just this sub-range" API, but its own ~100ms position
  /// polling (which already drives this listener) is precise enough to loop
  /// a status-length clip convincingly.
  void _handleTrimLoopPosition() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    // A rewind is already in flight. Reporting the intermediate positions it
    // passes through is what made the playhead crawl backwards across the
    // strip; everything moves at once when the rewind lands instead.
    if (_isRewindingToTrimStart) {
      return;
    }

    final value = controller.value;
    final trimEnd = _trimStartSeconds + _durationSeconds;
    final positionSeconds = value.position.inMilliseconds / 1000;

    // isCompleted is set synchronously with the end-of-clip event, while the
    // pause and seek VideoPlayerController performs in response land a frame
    // or two later. Reacting to it here -- rather than to the pause -- is
    // what keeps the play button from appearing before the rewind.
    if (value.isCompleted || positionSeconds >= trimEnd) {
      unawaited(
        _rewindToTrimStart(
          controller,
          resume: _isVideoPlaying && !value.isCompleted,
        ),
      );
      return;
    }

    _videoPosition.value = positionSeconds;
    _syncPlayingFlagFrom(controller);
  }

  /// Returns to the start of the trimmed range.
  ///
  /// [resume] keeps a trimmed range looping: the player is still running
  /// when the range ends short of the clip, so it only needs rewinding. At
  /// the clip's own end the player has already stopped and staying stopped
  /// is correct -- what matters there is that the rewind and the play button
  /// appear together.
  ///
  /// The playhead and the button are both updated in the one synchronous
  /// block below, so they land in the same frame and read as a single reset
  /// rather than a button that appears and a video that catches up.
  Future<void> _rewindToTrimStart(
    VideoPlayerController controller, {
    required bool resume,
  }) async {
    _isRewindingToTrimStart = true;
    try {
      await controller.seekTo(Duration(milliseconds: _trimStartMillis));
      if (resume && !controller.value.isPlaying) {
        await controller.play();
      }
    } catch (_) {
      // A failed rewind must not wedge the flag below.
    } finally {
      _isRewindingToTrimStart = false;
    }

    if (!mounted) {
      return;
    }
    // One synchronous block: the playhead lands at the start and the play
    // button appears in the same frame, so it reads as a single reset.
    _videoPosition.value = _trimStartSeconds;
    final isPlaying = controller.value.isPlaying;
    if (isPlaying != _isVideoPlaying) {
      setState(() => _isVideoPlaying = isPlaying);
    }
  }

  /// Keeps the play/pause overlay honest.
  ///
  /// [_isVideoPlaying] used to be written only by the tap handler, so it
  /// recorded what the user asked for rather than what the player is doing.
  /// Anything that stopped playback on its own -- reaching the end, an
  /// error, the audio session being taken away -- left the flag stuck at
  /// true and the play button hidden, with no way to start the video again.
  void _syncPlayingFlagFrom(VideoPlayerController controller) {
    final isPlaying = controller.value.isPlaying;
    if (!mounted || isPlaying == _isVideoPlaying) {
      return;
    }

    if (!isPlaying) {
      // Stopped without being asked -- the clip ended, an error, the audio
      // session was taken away. Show the play button only once the rewind
      // has landed, so the reset is one event rather than a button that
      // appears and a video that catches up a few frames later.
      //
      // Deliberately not keyed off `isCompleted`: VideoPlayerController
      // pauses (which notifies, with isCompleted still false) *before* it
      // marks the clip complete, so anything watching that flag reacts a
      // beat too late. A manual pause never reaches here -- the tap handler
      // sets the flag itself, so this only sees stops nobody asked for.
      unawaited(_rewindToTrimStart(controller, resume: false));
      return;
    }

    setState(() => _isVideoPlaying = true);
  }

  /// A music track always overrides the video's own audio, same as the
  /// posted story's own playback logic -- muting is only meaningful when
  /// no music is layered on top.
  double get _effectiveVideoVolume => (_isMuted || _musicTrack != null) ? 0 : 1;

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    if (_musicTrack == null) {
      unawaited(_videoController?.setVolume(_effectiveVideoVolume));
    }
  }

  void _toggleVideoPlayback() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final nextPlaying = !_isVideoPlaying;
    setState(() {
      _isVideoPlaying = nextPlaying;
    });
    if (nextPlaying) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  void _handleTrimScrubStart() {
    _wasPlayingBeforeTrimScrub = _isVideoPlaying;
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.pause());
    }
  }

  /// Seeks the live preview to whichever handle just moved -- WhatsApp's
  /// own trimmer shows the exact frame you're dragging to, not just an
  /// abstract range value.
  void _handleTrimScrubUpdate(RangeValues values, double previewSeconds) {
    setState(() {
      _trimStartSeconds = values.start;
      _durationSeconds = (values.end - values.start)
          .clamp(_minDurationSeconds, _maxDurationSeconds);
    });
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      unawaited(
        controller.seekTo(
          Duration(milliseconds: (previewSeconds * 1000).round()),
        ),
      );
    }
  }

  void _handleTrimScrubEnd() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    unawaited(
      controller.seekTo(Duration(milliseconds: _trimStartMillis)),
    );
    if (_wasPlayingBeforeTrimScrub) {
      unawaited(controller.play());
    }
  }

  void _shareStatus() {
    _commitInlineTextEditing(clearSelection: false);
    Navigator.of(context).pop(
      MediaStatusComposerDraft(
        // WhatsApp/Instagram's plain "Add a caption..." field is its own
        // independent input, never merged with the rich "Add text"
        // overlay's own label -- both can be present at once and should
        // both show up when the story is viewed (see
        // _RichStatusMediaDecorationOverlay in status_media_decoration_
        // overlay.dart, which renders the caption alongside overlay
        // items rather than picking one or the other).
        caption: _captionController.text.trim(),
        textStyle: _summaryTextStyle,
        mediaTransform: _mediaTransform,
        overlayItems: _normalizedShareableOverlayItems(),
        emoji: _leadEmoji,
        stickers: _stickerLabels,
        musicTrack: _musicTrack,
        durationMillis: _durationMillis,
        trimStartMillis: _trimStartMillis,
        drawingStrokes: List<StatusDrawingStroke>.unmodifiable(_drawingStrokes),
      ),
    );
  }

  String _nextOverlayId(String prefix) {
    final nextId = '$prefix-$_nextOverlaySeed';
    _nextOverlaySeed += 1;
    return nextId;
  }

  Offset _suggestedNormalizedPosition({
    double baseDx = 0.5,
    double baseDy = 0.5,
  }) {
    const offsets = <Offset>[
      Offset(0, 0),
      Offset(-0.12, -0.08),
      Offset(0.12, -0.05),
      Offset(-0.08, 0.12),
      Offset(0.1, 0.14),
    ];
    final delta = offsets[_overlayItems.length % offsets.length];
    return Offset(
      (baseDx + delta.dx)
          .clamp(_minOverlayPosition, _maxOverlayPosition)
          .toDouble(),
      (baseDy + delta.dy)
          .clamp(_minOverlayPosition, _maxOverlayPosition)
          .toDouble(),
    );
  }

  Size _estimatedOverlayFootprint(
    StatusMediaOverlayItem item, {
    required double scale,
  }) {
    switch (item.type) {
      case StatusMediaOverlayType.text:
        final text = item.label.trim();
        final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
        final longestLine = text
            .split('\n')
            .fold<int>(0, (current, line) => math.max(current, line.length));
        final style = item.textStyle ?? _defaultTextOverlayStyle;
        final fontScale = style.sizeScale
            .clamp(kStatusTextMinSizeScale, kStatusTextMaxSizeScale);
        final estimatedWidth =
            (math.max(longestLine, 6) * 12.5 * fontScale + 58)
                .clamp(136.0, 300.0);
        final estimatedHeight =
            (lines * 30 * fontScale + 30).clamp(58.0, 220.0);
        return Size(
          estimatedWidth * scale,
          estimatedHeight * scale,
        );
      case StatusMediaOverlayType.emoji:
        return Size.square(74 * scale);
      case StatusMediaOverlayType.sticker:
        return Size(
          164 * scale,
          62 * scale,
        );
      case StatusMediaOverlayType.music:
        return Size(
          214 * scale,
          72 * scale,
        );
    }
  }

  Offset _clampOverlayPosition({
    required StatusMediaOverlayItem item,
    required Size canvasSize,
    required double positionDx,
    required double positionDy,
    required double scale,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return const Offset(0.5, 0.5);
    }

    final footprint = _estimatedOverlayFootprint(
      item,
      scale: scale.clamp(0.6, 3.0),
    );

    final safeRect = _composerOverlaySafeRectForFrame(canvasSize);
    final centerDx =
        (safeRect.center.dx / canvasSize.width).clamp(0.0, 1.0).toDouble();
    final centerDy =
        (safeRect.center.dy / canvasSize.height).clamp(0.0, 1.0).toDouble();

    final minDx = ((safeRect.left + (footprint.width / 2)) / canvasSize.width)
        .clamp(_minOverlayPosition, centerDx)
        .toDouble();
    final maxDx = ((safeRect.right - (footprint.width / 2)) / canvasSize.width)
        .clamp(minDx, _maxOverlayPosition)
        .toDouble();
    final minDy = ((safeRect.top + (footprint.height / 2)) / canvasSize.height)
        .clamp(_minOverlayPosition, centerDy)
        .toDouble();
    final maxDy =
        ((safeRect.bottom - (footprint.height / 2)) / canvasSize.height)
            .clamp(minDy, _maxOverlayPosition)
            .toDouble();

    return Offset(
      positionDx.clamp(minDx, maxDx).toDouble(),
      positionDy.clamp(minDy, maxDy).toDouble(),
    );
  }

  Size _composerSafeAreaSize(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return Size(
      screenSize.width,
      math.max(screenSize.height - padding.top - padding.bottom, 0),
    );
  }

  Size _overlayFrameSizeForCurrentContext() {
    return _mediaFrameSizeFor(_composerSafeAreaSize(context));
  }

  StatusMediaOverlayItem _normalizedOverlayItemForCurrentFrame(
    StatusMediaOverlayItem item, {
    Size? frameSize,
    bool clampPosition = true,
  }) {
    final effectiveFrameSize =
        frameSize ?? _overlayFrameSizeForCurrentContext();
    final normalizedScale = item.scale.clamp(0.6, 3.0).toDouble();
    if (!clampPosition) {
      return item.copyWith(scale: normalizedScale);
    }
    if (effectiveFrameSize.width <= 0 || effectiveFrameSize.height <= 0) {
      return item;
    }

    final clampedPosition = _clampOverlayPosition(
      item: item,
      canvasSize: effectiveFrameSize,
      positionDx: item.positionDx,
      positionDy: item.positionDy,
      scale: normalizedScale,
    );
    return item.copyWith(
      positionDx: clampedPosition.dx,
      positionDy: clampedPosition.dy,
      scale: normalizedScale,
    );
  }

  List<StatusMediaOverlayItem> _normalizedShareableOverlayItems() {
    final frameSize = _overlayFrameSizeForCurrentContext();
    return List<StatusMediaOverlayItem>.unmodifiable(
      _shareableOverlayItems.map(
        (item) => _normalizedOverlayItemForCurrentFrame(
          item,
          frameSize: frameSize,
        ),
      ),
    );
  }

  void _selectOverlay(String overlayId, {bool bringToFront = true}) {
    _overlayGuideTimer?.cancel();
    setState(() {
      _resetMediaGestureState();
      _selectedOverlayId = overlayId;
      _showOverlayGuide = true;
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
      if (!bringToFront) {
        return;
      }

      final index = _overlayItems.indexWhere((item) => item.id == overlayId);
      if (index == -1 || index == _overlayItems.length - 1) {
        return;
      }

      final item = _overlayItems.removeAt(index);
      _overlayItems.add(item);
    });
  }

  void _handleOverlayTap(StatusMediaOverlayItem item) {
    if (_isEditingTextOverlay && _editingTextOverlayId != item.id) {
      _commitInlineTextEditing(clearSelection: true);
    }
    // A single tap on placed text reopens the full editing view directly --
    // matching WhatsApp, and there's nothing left for an intermediate
    // "selected but not editing" state to show now that Done fully
    // deselects (see onDoneEditing above), so a two-tap select-then-edit
    // step would just be a dead end.
    if (item.type == StatusMediaOverlayType.text) {
      _beginInlineTextEditing(item);
      return;
    }
    _selectOverlay(item.id);
    _scheduleOverlayGuideHide();
  }

  void _handleCanvasTap() {
    if (_isEditingTextOverlay) {
      _commitInlineTextEditing(clearSelection: true);
      return;
    }
    // Tapping empty video area toggles playback, same as any standard
    // video player and WhatsApp's own status editor -- this is the only
    // way back to playing once paused besides the overlay button itself.
    if (_isVideo && !_isCropMode && !_isDrawMode) {
      _toggleVideoPlayback();
    }
    _clearSelection();
  }

  void _clearSelection() {
    _overlayGuideTimer?.cancel();
    if (_selectedOverlayId == null &&
        _editingTextOverlayId == null &&
        !_showOverlayGuide) {
      return;
    }
    setState(() {
      _resetMediaGestureState();
      _selectedOverlayId = null;
      _editingTextOverlayId = null;
      _showOverlayGuide = false;
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
    _inlineTextFocusNode.unfocus();
  }

  void _upsertOverlay(
    StatusMediaOverlayItem item, {
    bool select = true,
    bool clampPosition = true,
  }) {
    final normalizedItem = _normalizedOverlayItemForCurrentFrame(
      item,
      clampPosition: clampPosition,
    );
    setState(() {
      _overlayItems.removeWhere((entry) => entry.id == normalizedItem.id);
      _overlayItems.add(normalizedItem);
      if (select) {
        _selectedOverlayId = normalizedItem.id;
      }
    });
  }

  void _removeOverlay(String overlayId) {
    final index = _overlayItems.indexWhere((item) => item.id == overlayId);
    if (index == -1) {
      return;
    }

    final item = _overlayItems[index];
    setState(() {
      _resetMediaGestureState();
      _gestureAnchorOverlay = null;
      _gestureStartFocalPoint = null;
      _overlayItems.removeAt(index);
      if (item.type == StatusMediaOverlayType.music) {
        _musicTrack = null;
        _previewingMusicTrackId = null;
        // Music removed -- give the video its own audio back, unless the
        // user had muted it themselves.
        unawaited(_videoController?.setVolume(_effectiveVideoVolume));
      }
      if (_selectedOverlayId == overlayId) {
        _selectedOverlayId = null;
      }
      if (_editingTextOverlayId == overlayId) {
        _editingTextOverlayId = null;
      }
      if (_overlayItems.isEmpty) {
        _showOverlayGuide = false;
      }
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
    if (_editingTextOverlayId == null) {
      _inlineTextFocusNode.unfocus();
    }
    if (item.type == StatusMediaOverlayType.music) {
      unawaited(_stopMusicPreview());
    }
  }

  void _addTextOverlay() {
    _overlayGuideTimer?.cancel();
    // Center of the frame, matching WhatsApp's own default -- also matches
    // where the dedicated editing card renders it while the keyboard is up
    // (see _isEditingTextOverlay in build()), so tapping Done doesn't jump
    // the text to a different spot than where it was just typed.
    final position = _suggestedNormalizedPosition(baseDx: 0.5, baseDy: 0.5);
    final overlay = StatusMediaOverlayItem(
      id: _nextOverlayId('text'),
      type: StatusMediaOverlayType.text,
      label: '',
      positionDx: position.dx,
      positionDy: position.dy,
      scale: 1,
      rotation: 0,
      textStyle: _defaultTextOverlayStyle,
    );
    _upsertOverlay(overlay);
    _beginInlineTextEditing(overlay);
  }

  // Shared by the top bar's alignment/decoration icons, both only ever
  // shown while actively editing (see _buildTopRow's gating).
  void _cycleTextAlignment() {
    _updateSelectedTextStyle((style) {
      final nextAlignment = switch (style.alignment) {
        StatusTextAlignment.left => StatusTextAlignment.center,
        StatusTextAlignment.center => StatusTextAlignment.right,
        StatusTextAlignment.right => StatusTextAlignment.left,
      };
      return style.copyWith(alignment: nextAlignment);
    });
  }

  void _toggleTextBackground() {
    _updateSelectedTextStyle((style) {
      final nextSelected = !style.useSolidBackground;
      return style.copyWith(
        useSolidBackground: nextSelected,
        backgroundColorValue:
            nextSelected ? (style.backgroundColorValue ?? 0xCC101418) : null,
        clearBackgroundColor: !nextSelected,
      );
    });
  }

  void _beginInlineTextEditing(StatusMediaOverlayItem overlay) {
    _selectOverlay(overlay.id);
    final text = overlay.label;
    _inlineTextController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _editingTextOverlayId = overlay.id;
      _showOverlayGuide = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _inlineTextFocusNode.requestFocus();
    });
  }

  void _handleInlineTextChanged() {
    final overlayId = _editingTextOverlayId;
    if (overlayId == null) {
      return;
    }
    final index = _overlayItems.indexWhere((item) => item.id == overlayId);
    if (index == -1) {
      return;
    }
    final overlay = _overlayItems[index];
    final nextLabel = _inlineTextController.text;
    if (overlay.label == nextLabel) {
      return;
    }
    _upsertOverlay(
      overlay.copyWith(label: nextLabel),
      select: true,
    );
  }

  void _commitInlineTextEditing({required bool clearSelection}) {
    final overlayId = _editingTextOverlayId;
    if (overlayId == null) {
      if (clearSelection) {
        _clearSelection();
      }
      return;
    }

    final trimmedText = _inlineTextController.text.trim();
    if (trimmedText.isEmpty) {
      _removeOverlay(overlayId);
    } else {
      final index = _overlayItems.indexWhere((item) => item.id == overlayId);
      if (index != -1) {
        _upsertOverlay(
          _overlayItems[index].copyWith(label: _inlineTextController.text),
          select: true,
        );
      }
    }

    _overlayGuideTimer?.cancel();
    setState(() {
      _editingTextOverlayId = null;
      if (clearSelection) {
        _selectedOverlayId = null;
        _showOverlayGuide = false;
      }
    });
    _inlineTextFocusNode.unfocus();
    if (!clearSelection) {
      _scheduleOverlayGuideHide();
    }
  }

  void _updateSelectedTextStyle(
    StatusTextStyle Function(StatusTextStyle style) transform,
  ) {
    final selectedOverlay = _selectedOverlay;
    if (selectedOverlay == null ||
        selectedOverlay.type != StatusMediaOverlayType.text) {
      return;
    }

    _upsertOverlay(
      selectedOverlay.copyWith(
        textStyle: transform(
          selectedOverlay.textStyle ?? _defaultTextOverlayStyle,
        ),
      ),
      select: true,
    );
    setState(() {
      _showOverlayGuide = true;
    });
  }

  void _scheduleOverlayGuideHide(
      [Duration delay = const Duration(milliseconds: 900)]) {
    if (_isEditingTextOverlay) {
      return;
    }
    _overlayGuideTimer?.cancel();
    _overlayGuideTimer = Timer(delay, () {
      if (!mounted || _isEditingTextOverlay) {
        return;
      }
      setState(() {
        _showOverlayGuide = false;
      });
    });
  }

  /// One combined sheet for both -- matching WhatsApp's own picker, which
  /// isn't two separate tools, just one scroll with stickers on top and
  /// emoji below.
  Future<void> _openStickerAndEmojiPicker() async {
    final result = await showGlassBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _StickerAndEmojiPickerSheet(stickerPresets: _stickerPresets);
      },
    );
    if (!mounted || result == null) {
      return;
    }

    if (result is _StickerPreset) {
      if (result.label.trim().isEmpty) {
        return;
      }
      final position = _suggestedNormalizedPosition(baseDx: 0.48, baseDy: 0.34);
      _upsertOverlay(
        StatusMediaOverlayItem(
          id: _nextOverlayId('sticker'),
          type: StatusMediaOverlayType.sticker,
          label: result.label.trim(),
          positionDx: position.dx,
          positionDy: position.dy,
          scale: 1,
          rotation: 0,
          accentColorValue: result.accentColorValue,
          secondaryColorValue: result.secondaryColorValue,
          variantId: result.id,
        ),
      );
    } else if (result is String && result.isNotEmpty) {
      final position = _suggestedNormalizedPosition(baseDx: 0.72, baseDy: 0.28);
      _upsertOverlay(
        StatusMediaOverlayItem(
          id: _nextOverlayId('emoji'),
          type: StatusMediaOverlayType.emoji,
          label: result,
          positionDx: position.dx,
          positionDy: position.dy,
          scale: 1.18,
          rotation: 0,
        ),
      );
    }
  }

  /// The "Add music" catalog now always loads from the server (Firestore
  /// metadata pointing at Firebase Storage-hosted mp3s) instead of a
  /// bundled asset list -- cached for the rest of this composer session so
  /// reopening the picker doesn't refetch every time.
  Future<List<StatusMusicTrack>> _loadMusicTracksAndCache() async {
    final cached = _cachedMusicTracks;
    if (cached != null) {
      return cached;
    }
    final loader =
        widget.loadMusicTracks ?? (() async => kFallbackStatusMusicTracks);
    final tracks = await loader();
    _cachedMusicTracks = tracks;
    return tracks;
  }

  Future<void> _openMusicPicker() async {
    final theme = Theme.of(context);
    final tracksFuture = _loadMusicTracksAndCache();
    final selectedTrack = await showGlassBottomSheet<StatusMusicTrack?>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // The preview toggle updates this screen's state asynchronously
        // (after the player actually starts/stops), but a modal sheet's
        // `builder` only runs once -- without this StatefulBuilder the
        // play/pause icon in the list never reflected the new state, even
        // though the audio itself was toggling correctly underneath.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<StatusMusicTrack>>(
              future: tracksFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 240,
                    child: Center(
                      key: Key('updates_media_music_loading'),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return SizedBox(
                    height: 240,
                    child: Center(
                      child: Text(
                        'Could not load music right now.',
                        key: const Key('updates_media_music_load_error'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                return _MusicPickerSheet(
                  tracks: snapshot.data!,
                  selectedTrackId: _musicTrack?.id,
                  previewingTrackId: _previewingMusicTrackId,
                  onPlayPreview: (track) async {
                    await _playMusicPreview(track, toggleWhenSameTrack: true);
                    if (context.mounted) {
                      setSheetState(() {});
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
    if (!mounted) {
      return;
    }

    if (selectedTrack == null) {
      // Dismissed without picking: the preview must not keep playing behind
      // the closed sheet, which is the only place it can be stopped from.
      unawaited(_stopMusicPreview());
      return;
    }

    // Low enough to clear the trim filmstrip, which occupies the top of
    // the canvas on a video. At 0.16 the banner landed underneath it: the
    // strip took the drag, so the banner could not be moved off the spot
    // it was dropped on. Same band the emoji default uses, which is
    // already clear of it.
    final position = _suggestedNormalizedPosition(baseDx: 0.24, baseDy: 0.34);
    final overlay = StatusMediaOverlayItem(
      id: _overlayItems
              .cast<StatusMediaOverlayItem?>()
              .firstWhere(
                (item) => item?.type == StatusMediaOverlayType.music,
                orElse: () => null,
              )
              ?.id ??
          _nextOverlayId('music'),
      type: StatusMediaOverlayType.music,
      label: selectedTrack.title,
      subtitle: selectedTrack.artist,
      positionDx: position.dx,
      positionDy: position.dy,
      scale: 1,
      rotation: 0,
      accentColorValue: selectedTrack.colorValue,
      secondaryColorValue: selectedTrack.secondaryColorValue,
      variantId: selectedTrack.bannerStyleId,
    );

    // Music now overrides the video's own audio (matches the posted
    // story's own video-vs-music volume logic).
    unawaited(_videoController?.setVolume(0));
    setState(() {
      _musicTrack = selectedTrack;
      _overlayItems.removeWhere(
        (item) => item.type == StatusMediaOverlayType.music,
      );
      _overlayItems.add(overlay);
      _selectedOverlayId = overlay.id;
    });
    unawaited(_playMusicPreview(selectedTrack));
  }

  void _updateSelectedMusicStyle(String styleId) {
    final selectedOverlay = _selectedOverlay;
    if (selectedOverlay == null ||
        selectedOverlay.type != StatusMediaOverlayType.music) {
      return;
    }

    _upsertOverlay(
      selectedOverlay.copyWith(variantId: styleId),
      select: true,
    );
    setState(() {
      _musicTrack = _musicTrack?.copyWith(bannerStyleId: styleId);
      _showOverlayGuide = true;
    });
    _scheduleOverlayGuideHide();
  }

  void _onOverlayScaleStart(
    StatusMediaOverlayItem item,
    ScaleStartDetails details,
  ) {
    if (_isEditingTextOverlay && _editingTextOverlayId != item.id) {
      _commitInlineTextEditing(clearSelection: false);
    }
    _selectOverlay(item.id);
    _overlayGuideTimer?.cancel();
    setState(() {
      _resetMediaGestureState();
      _showOverlayGuide = true;
      _isDeleteTargetActive = false;
      _isDraggingOverlay = true;
    });
    _gestureAnchorOverlay = item;
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _onOverlayScaleUpdate(
    ScaleUpdateDetails details,
    Size canvasSize,
  ) {
    final anchorOverlay = _gestureAnchorOverlay;
    final gestureStartFocalPoint = _gestureStartFocalPoint;
    if (anchorOverlay == null ||
        gestureStartFocalPoint == null ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return;
    }

    final delta = details.focalPoint - gestureStartFocalPoint;
    final nextDx = ((anchorOverlay.positionDx * canvasSize.width) + delta.dx) /
        canvasSize.width;
    final nextDy = ((anchorOverlay.positionDy * canvasSize.height) + delta.dy) /
        canvasSize.height;
    final nextScale = (anchorOverlay.scale * details.scale).clamp(0.6, 3.0);

    // Deliberately unclamped while the finger is down -- the overlay must be
    // free to travel past the frame edges, all the way down to the delete
    // target below the canvas, exactly like WhatsApp. It only gets snapped
    // back inside the visible frame in _onOverlayScaleEnd, and only if the
    // drag didn't end on the delete target.
    _upsertOverlay(
      anchorOverlay.copyWith(
        positionDx: nextDx,
        positionDy: nextDy,
        scale: nextScale,
        rotation: anchorOverlay.rotation + details.rotation,
      ),
      clampPosition: false,
    );
    _updateDeleteTargetHover(
      globalFocalPoint: details.focalPoint,
      isDraggingOverlay: true,
    );
  }

  void _onOverlayScaleEnd(ScaleEndDetails details) {
    final overlayToDelete =
        _isDeleteTargetActive ? _gestureAnchorOverlay : null;
    final draggedOverlayId = _gestureAnchorOverlay?.id;
    _gestureAnchorOverlay = null;
    _gestureStartFocalPoint = null;
    setState(() {
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
    if (overlayToDelete != null) {
      _removeOverlay(overlayToDelete.id);
      return;
    }
    if (draggedOverlayId != null) {
      // Released without hitting the delete target -- now settle the
      // overlay back inside the visible frame (it was allowed to travel
      // past the frame edges during the drag itself).
      final index =
          _overlayItems.indexWhere((entry) => entry.id == draggedOverlayId);
      if (index != -1) {
        _upsertOverlay(_overlayItems[index]);
      }
    }
    _scheduleOverlayGuideHide();
  }

  void _onMediaScaleStart(ScaleStartDetails details) {
    if (!_allowMediaTransformGestures) {
      _resetMediaGestureState();
      return;
    }
    _mediaGestureAnchorTransform = _mediaTransform;
    _mediaGestureStartFocalPoint = details.focalPoint;
  }

  void _onMediaScaleUpdate(
    ScaleUpdateDetails details,
    Size canvasSize,
  ) {
    if (!_allowMediaTransformGestures) {
      _resetMediaGestureState();
      return;
    }
    final anchorTransform = _mediaGestureAnchorTransform;
    final startFocalPoint = _mediaGestureStartFocalPoint;
    if (anchorTransform == null ||
        startFocalPoint == null ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return;
    }

    // The media moves and zooms under a fixed frame, the way WhatsApp's
    // crop tool works. The selection is still *stored* as a window over the
    // media, so the gesture is translated rather than the model changed:
    // dragging the media one way slides the window the other, and pinching
    // the media larger makes the window enclose less of it.
    //
    // Deltas arrive in screen points and the window lives in media points,
    // so they are divided by the on-screen zoom -- otherwise the media
    // would race ahead of the finger at high magnification.
    final mediaBounds = _cropMediaBoundsFor(canvasSize);
    final ratio =
        statusCropRatioFor(canvasSize, anchorTransform.frameAspectRatio);
    final anchorWindow = cropWindowRectFor(
      mediaBounds,
      ratio,
      anchorTransform.scale,
      anchorTransform.offsetDx,
      anchorTransform.offsetDy,
    );
    if (anchorWindow.width <= 0 || anchorWindow.height <= 0) {
      return;
    }

    final cropFrame = statusCropFrameRectFor(
      canvasSize,
      anchorTransform.frameAspectRatio,
    );
    final zoom = cropFrame.width / anchorWindow.width;
    if (!zoom.isFinite || zoom <= 0) {
      return;
    }

    // Zooming in shrinks the window; it can never grow past the media.
    final nextScale =
        (anchorTransform.scale * details.scale).clamp(1.0, 8.0).toDouble();
    final fitSize = statusStoryFrameSizeFor(mediaBounds.size, ratio);
    final windowSize = Size(
      fitSize.width / nextScale,
      fitSize.height / nextScale,
    );
    if (windowSize.width <= 0 || windowSize.height <= 0) {
      return;
    }

    final delta = details.focalPoint - startFocalPoint;
    final desiredCenter = anchorWindow.center - delta / zoom;
    final minCenterX = mediaBounds.left + windowSize.width / 2;
    final maxCenterX =
        math.max(mediaBounds.right - windowSize.width / 2, minCenterX);
    final minCenterY = mediaBounds.top + windowSize.height / 2;
    final maxCenterY =
        math.max(mediaBounds.bottom - windowSize.height / 2, minCenterY);
    final clampedCenter = Offset(
      desiredCenter.dx.clamp(minCenterX, maxCenterX),
      desiredCenter.dy.clamp(minCenterY, maxCenterY),
    );

    setState(() {
      _mediaTransform = anchorTransform.copyWith(
        scale: nextScale,
        offsetDx: (mediaBounds.center.dx - clampedCenter.dx) / windowSize.width,
        offsetDy:
            (mediaBounds.center.dy - clampedCenter.dy) / windowSize.height,
      );
    });
  }

  /// Where the media actually paints on the crop canvas -- the crop window
  /// is confined to this, not the full canvas, so it can never be dragged
  /// or resized out over a letterbox bar where there's no media to crop.
  Rect _cropMediaBoundsFor(Size canvasSize) =>
      statusMediaBoundsFor(canvasSize, _effectiveOriginalAspectRatio);

  void _onMediaScaleEnd(ScaleEndDetails details) {
    _resetMediaGestureState();
  }

  /// The minimum crop window size (in canvas points) a corner drag can
  /// shrink the box to -- small enough to crop tightly, large enough to
  /// stay grabbable and to keep the derived scale finite/sane.
  static const double _kCropMinWindowSize = 56;

  Offset _cropWindowCornerPoint(_CropCorner corner, Rect window) =>
      switch (corner) {
        _CropCorner.topLeft => window.topLeft,
        _CropCorner.topRight => window.topRight,
        _CropCorner.bottomLeft => window.bottomLeft,
        _CropCorner.bottomRight => window.bottomRight,
      };

  Offset _cropWindowOppositeCornerPoint(_CropCorner corner, Rect window) =>
      switch (corner) {
        _CropCorner.topLeft => window.bottomRight,
        _CropCorner.topRight => window.bottomLeft,
        _CropCorner.bottomLeft => window.topRight,
        _CropCorner.bottomRight => window.topLeft,
      };

  // [displayPoint] seeds the running drag point from wherever the user's
  // finger actually grabbed the handle, so the box tracks the finger 1:1
  // with no jump.
  /// Screen points per media point while the crop frame is on screen.
  ///
  /// The frame is fixed and the media is scaled to put the selection inside
  /// it, so a finger travelling one point on glass moves the selection by
  /// less than a point across the media whenever it is magnified.
  double _cropScreenToWindowZoom(Size canvasSize) {
    return statusCropProjection(
      canvasSize: canvasSize,
      window: cropWindowRectFor(
        _cropMediaBoundsFor(canvasSize),
        statusCropRatioFor(canvasSize, _mediaTransform.frameAspectRatio),
        _mediaTransform.scale,
        _mediaTransform.offsetDx,
        _mediaTransform.offsetDy,
      ),
      // Frozen mid-resize, so the corner keeps tracking the finger 1:1
      // rather than accelerating as the selection tightens.
      anchorWindow: _cropResizeAnchorWindow,
      ratio: _mediaTransform.frameAspectRatio,
    ).zoom;
  }

  /// Maps a point on glass to the media-space point under it.
  Offset _cropScreenPointToWindow(Offset screenPoint, Size canvasSize) {
    final zoom = _cropScreenToWindowZoom(canvasSize);
    final frame = statusCropFrameRectFor(
      canvasSize,
      _mediaTransform.frameAspectRatio,
    );
    final window = cropWindowRectFor(
      _cropMediaBoundsFor(canvasSize),
      statusCropRatioFor(canvasSize, _mediaTransform.frameAspectRatio),
      _mediaTransform.scale,
      _mediaTransform.offsetDx,
      _mediaTransform.offsetDy,
    );
    return window.center + (screenPoint - frame.center) / zoom;
  }

  void _onCropCornerPanStart(
    _CropCorner corner,
    Size canvasSize,
    Offset displayPoint,
  ) {
    if (!_allowMediaTransformGestures) {
      return;
    }
    final window = cropWindowRectFor(
      _cropMediaBoundsFor(canvasSize),
      statusCropRatioFor(canvasSize, _mediaTransform.frameAspectRatio),
      _mediaTransform.scale,
      _mediaTransform.offsetDx,
      _mediaTransform.offsetDy,
    );
    setState(() {
      // Rebuild so the media freezes for the duration of the drag.
      _cropResizeAnchorWindow = window;
    });
    _cropResizeActiveCorner = corner;
    // The handle is handed a frame corner in screen space; the resize maths
    // below all runs in media space.
    _cropResizeCurrentPoint =
        _cropScreenPointToWindow(displayPoint, canvasSize);
  }

  void _onCropCornerPanUpdate(DragUpdateDetails details, Size canvasSize) {
    final anchorWindow = _cropResizeAnchorWindow;
    final corner = _cropResizeActiveCorner;
    final currentPoint = _cropResizeCurrentPoint;
    if (anchorWindow == null || corner == null || currentPoint == null) {
      return;
    }

    final mediaBounds = _cropMediaBoundsFor(canvasSize);
    final fixedCorner = _cropWindowOppositeCornerPoint(corner, anchorWindow);
    final draggedPoint =
        currentPoint + details.delta / _cropScreenToWindowZoom(canvasSize);
    _cropResizeCurrentPoint = draggedPoint;

    // Clamp to the *media's* bounds (not the canvas -- dragging out over a
    // letterbox bar would select empty space), and keep at least the
    // minimum window size away from the fixed (opposite) corner. Direction
    // comes from which corner handle this is, not from comparing against
    // the fixed corner, so the box can never flip inside-out under a fast
    // drag.
    final isLeftHandle =
        corner == _CropCorner.topLeft || corner == _CropCorner.bottomLeft;
    final isTopHandle =
        corner == _CropCorner.topLeft || corner == _CropCorner.topRight;
    var x = draggedPoint.dx.clamp(mediaBounds.left, mediaBounds.right);
    var y = draggedPoint.dy.clamp(mediaBounds.top, mediaBounds.bottom);
    if (isLeftHandle) {
      x = math.min(x, fixedCorner.dx - _kCropMinWindowSize);
      x = math.max(x, mediaBounds.left);
    } else {
      x = math.max(x, fixedCorner.dx + _kCropMinWindowSize);
      x = math.min(x, mediaBounds.right);
    }
    if (isTopHandle) {
      y = math.min(y, fixedCorner.dy - _kCropMinWindowSize);
      y = math.max(y, mediaBounds.top);
    } else {
      y = math.max(y, fixedCorner.dy + _kCropMinWindowSize);
      y = math.min(y, mediaBounds.bottom);
    }

    final newWindow = Rect.fromPoints(fixedCorner, Offset(x, y));
    if (newWindow.width <= 0 || newWindow.height <= 0) {
      return;
    }
    final ratio = newWindow.width / newWindow.height;
    final fitSize = statusStoryFrameSizeFor(mediaBounds.size, ratio);
    final newScale = fitSize.width / newWindow.width;

    setState(() {
      _isFitToScreenCrop = false;
      _mediaTransform = _mediaTransform.copyWith(
        frameAspectRatio: ratio,
        scale: newScale,
        offsetDx:
            -(newWindow.center.dx - mediaBounds.center.dx) / newWindow.width,
        offsetDy:
            -(newWindow.center.dy - mediaBounds.center.dy) / newWindow.height,
      );
    });
  }

  void _onCropCornerPanEnd(DragEndDetails details) {
    _settleCropResize();
    _resetCropCornerGestureState();
  }

  /// Runs the post-resize re-fit as an animation rather than a jump.
  void _settleCropResize() => _animateCropSettleFrom(_cropResizeAnchorWindow);

  /// The window handed to the surface: the live selection normally, the
  /// frozen one mid-drag, and the settling one in between.
  Rect? get _cropProjectionAnchor {
    final tween = _cropSettleTween;
    if (tween != null && _cropSettleController.isAnimating) {
      return tween.evaluate(
        CurvedAnimation(
          parent: _cropSettleController,
          curve: kStatusMotionCurve,
        ),
      );
    }
    return _cropResizeAnchorWindow;
  }

  void _resetCropCornerGestureState() {
    final wasResizing = _cropResizeAnchorWindow != null;
    _cropResizeAnchorWindow = null;
    _cropResizeActiveCorner = null;
    _cropResizeCurrentPoint = null;
    if (wasResizing && mounted) {
      setState(() {});
    }
  }

  void _toggleDrawMode() {
    setState(() {
      _isDrawMode = !_isDrawMode;
      _liveStrokePoints = null;
    });
  }

  /// Converts a raw local gesture position (in the outer canvas box) into
  /// frame-normalized [0,1] coordinates -- the frame is centered within,
  /// and can be smaller than, that canvas box (letterboxing), matching
  /// exactly how `StatusStoryMediaSurface` centers and sizes its own frame.
  Offset _framePointFromLocal(Offset localPoint, Size canvasSize) {
    final frameSize = _mediaFrameSizeFor(canvasSize);
    if (frameSize.width <= 0 || frameSize.height <= 0) {
      return Offset.zero;
    }
    final frameOrigin = Offset(
      (canvasSize.width - frameSize.width) / 2,
      (canvasSize.height - frameSize.height) / 2,
    );
    final framePoint = localPoint - frameOrigin;
    return Offset(
      (framePoint.dx / frameSize.width).clamp(0.0, 1.0),
      (framePoint.dy / frameSize.height).clamp(0.0, 1.0),
    );
  }

  void _handleDrawPanStart(DragStartDetails details, Size canvasSize) {
    setState(() {
      _liveStrokePoints = <Offset>[
        _framePointFromLocal(details.localPosition, canvasSize),
      ];
    });
  }

  void _handleDrawPanUpdate(DragUpdateDetails details, Size canvasSize) {
    final points = _liveStrokePoints;
    if (points == null) {
      return;
    }
    setState(() {
      _liveStrokePoints = <Offset>[
        ...points,
        _framePointFromLocal(details.localPosition, canvasSize),
      ];
    });
  }

  void _handleDrawPanEnd(DragEndDetails details) {
    final points = _liveStrokePoints;
    setState(() {
      if (points != null && points.length > 1) {
        _drawingStrokes.add(
          StatusDrawingStroke(
            points: List<Offset>.unmodifiable(points),
            colorValue: _drawColor.toARGB32(),
            strokeWidth: _drawStrokeWidth,
            isEraser: _isEraserMode,
          ),
        );
      }
      _liveStrokePoints = null;
    });
  }

  void _undoLastStroke() {
    if (_drawingStrokes.isEmpty) {
      return;
    }
    setState(() {
      _drawingStrokes.removeLast();
    });
  }

  List<StatusDrawingStroke> get _displayedDrawingStrokes {
    final liveStroke = _liveStrokePoints;
    if (liveStroke == null || liveStroke.length < 2) {
      return _drawingStrokes;
    }
    return <StatusDrawingStroke>[
      ..._drawingStrokes,
      StatusDrawingStroke(
        points: liveStroke,
        colorValue: _drawColor.toARGB32(),
        strokeWidth: _drawStrokeWidth,
        isEraser: _isEraserMode,
      ),
    ];
  }

  void _rotateMediaClockwise() {
    setState(() {
      // A crop frame is a plain width/height ratio with no memory of the
      // content's rotation -- statusStoryFrameSizeFor has no way to know a
      // 4:3 landscape frame should become 3:4 portrait once the media
      // inside it spins 90 degrees, so that has to happen here, at the one
      // place the rotation actually changes.
      final currentRatio = _mediaTransform.frameAspectRatio;
      _mediaTransform = _mediaTransform.copyWith(
        rotationQuarterTurns: _mediaTransform.rotationQuarterTurns + 1,
        frameAspectRatio: currentRatio == null ? null : 1 / currentRatio,
      );
    });
  }

  Size _mediaFrameSizeFor(Size canvasSize) {
    return statusStoryFrameSizeFor(
      canvasSize,
      _mediaTransform.frameAspectRatio,
    );
  }

  /// The original media's aspect ratio, adjusted for the current rotation
  /// -- what "Original" in the crop tray should restore.
  double? get _effectiveOriginalAspectRatio {
    final original = _originalMediaAspectRatio;
    if (original == null) {
      return null;
    }
    return _mediaTransform.rotationQuarterTurns.isOdd ? 1 / original : original;
  }

  /// Straightens the media. See [StatusMediaTransform.rotationDegrees].
  void _setRotationDegrees(double degrees) {
    if (degrees == _mediaTransform.rotationDegrees) {
      return;
    }
    setState(() {
      _mediaTransform = _mediaTransform.copyWith(rotationDegrees: degrees);
    });
  }

  /// The selection in media space, or null before the crop tool has been
  /// laid out.
  Rect? get _currentCropWindow {
    final canvasSize = _lastCropCanvasSize;
    if (canvasSize == null) {
      return null;
    }
    return cropWindowRectFor(
      _cropMediaBoundsFor(canvasSize),
      statusCropRatioFor(canvasSize, _mediaTransform.frameAspectRatio),
      _mediaTransform.scale,
      _mediaTransform.offsetDx,
      _mediaTransform.offsetDy,
    );
  }

  /// Eases from [from] to wherever the selection has just been moved to.
  void _animateCropSettleFrom(Rect? from) {
    final to = _currentCropWindow;
    if (from == null || to == null || to.width <= 0 || from == to) {
      return;
    }
    _cropSettleTween = RectTween(begin: from, end: to);
    _cropSettleController.forward(from: 0);
  }

  void _toggleCropMode() {
    if (_isCropMode) {
      // Leaving: keep rendering the tool until the frame has travelled back
      // to the preview's framing, then drop it.
      _cropModeController.reverse().whenComplete(() {
        if (mounted) {
          setState(() => _isCropMode = false);
        }
      });
      return;
    }
    setState(() => _isCropMode = true);
    _cropModeController.forward(from: 0);
  }

  /// How far into the crop tool the UI currently is, 0..1.
  double get _cropTransition => _cropModeCurve.value.clamp(0.0, 1.0);

  void _selectCropAspectOption(_CropAspectOption option) {
    // Where the selection sits right now, so the change of shape can be
    // travelled rather than jumped.
    final before = _currentCropWindow;
    setState(() {
      // Picking a preset always re-centers and un-zooms the window to a
      // clean box of that shape -- any previous free-form corner-drag
      // resize/move is a stale answer to a different question once the
      // ratio itself has changed underneath it.
      _cropResizeAnchorWindow = null;
      _cropResizeActiveCorner = null;
      _cropResizeCurrentPoint = null;
      if (option.isOriginal) {
        _isFitToScreenCrop = false;
        final original = _effectiveOriginalAspectRatio;
        _mediaTransform = _mediaTransform.copyWith(
          frameAspectRatio: original,
          clearFrameAspectRatio: original == null,
          scale: 1,
          offsetDx: 0,
          offsetDy: 0,
        );
      } else if (option.ratio == null) {
        // Fit to screen -- no fixed shape at all, fills the available space.
        _isFitToScreenCrop = true;
        _mediaTransform = _mediaTransform.copyWith(
          clearFrameAspectRatio: true,
          scale: 1,
          offsetDx: 0,
          offsetDy: 0,
        );
      } else {
        _isFitToScreenCrop = false;
        _mediaTransform = _mediaTransform.copyWith(
          frameAspectRatio: option.ratio,
          scale: 1,
          offsetDx: 0,
          offsetDy: 0,
        );
      }
    });
    _animateCropSettleFrom(before);
  }

  /// Whether the crop frame differs from the media's own original frame in
  /// any way -- position, free-form size, or aspect ratio. Drives whether
  /// "Reset" is offered at all, so it stays in lockstep with what
  /// [_resetMediaTransformOffset] actually undoes.
  bool get _hasCropEdits {
    if (_mediaTransform.scale != 1 ||
        _mediaTransform.offsetDx != 0 ||
        _mediaTransform.offsetDy != 0 ||
        _mediaTransform.rotationDegrees != 0) {
      return true;
    }
    final current = _mediaTransform.frameAspectRatio;
    final original = _effectiveOriginalAspectRatio;
    // Both null means the media's own ratio is still unresolved and the
    // frame is unconstrained -- that *is* the original state, not an edit
    // (_matchesAspectRatio reports false for a null pair).
    if (current == null && original == null) {
      return false;
    }
    return !_matchesAspectRatio(current, original);
  }

  /// Undoes every crop edit -- window position, free-form size, and the
  /// aspect ratio itself -- putting the crop frame back on the media's own
  /// original, uncropped frame, matching the "Reset" action in WhatsApp's
  /// own crop screen. Rotation is left alone: it has its own button and
  /// isn't part of the crop selection.
  void _resetMediaTransformOffset() {
    final before = _currentCropWindow;
    setState(() {
      _isFitToScreenCrop = false;
      _cropResizeAnchorWindow = null;
      _cropResizeActiveCorner = null;
      _cropResizeCurrentPoint = null;
      final original = _effectiveOriginalAspectRatio;
      _mediaTransform = _mediaTransform.copyWith(
        frameAspectRatio: original,
        clearFrameAspectRatio: original == null,
        scale: 1,
        offsetDx: 0,
        offsetDy: 0,
        // Straightening is part of the crop selection, unlike the 90-degree
        // rotate, which has its own button and its own meaning.
        rotationDegrees: 0,
      );
    });
    _animateCropSettleFrom(before);
  }

  void _toggleBlurMode() {
    setState(() {
      _isBlurMode = !_isBlurMode;
    });
  }

  void _setBlurSigma(double sigma) {
    setState(() {
      _mediaTransform = _mediaTransform.copyWith(blurSigma: sigma);
    });
  }

  /// The picked ratio doesn't always match one of the presets exactly --
  /// dragging a corner handle in the free-form grid can land on anything.
  String get _currentCropRatioLabel {
    final ratio = _mediaTransform.frameAspectRatio;
    if (ratio == null) {
      return _isFitToScreenCrop ? 'Fit to screen' : 'Original';
    }
    for (final option in _cropAspectOptions) {
      if (option.ratio != null && (option.ratio! - ratio).abs() < 0.001) {
        return option.label;
      }
    }
    return 'Custom';
  }

  /// The top-of-screen row: close plus whichever controls belong to the
  /// active mode -- the full add-tool toolbar by default, a done/undo pair
  /// while cropping/drawing/blurring, or the existing text-selection
  /// close+edit pair. Always visible, in the same place, so it never has
  /// to slide the media around to make room the way the old bottom-tray
  /// swap did.
  /// Identifies which chrome variant is on screen, so the cross-fades know
  /// a real mode change happened rather than an ordinary rebuild.
  String get _activeToolModeKey {
    if (_isCropMode) return 'crop';
    if (_isDrawMode) return 'draw';
    if (_isBlurMode) return 'blur';
    if (_isEditingTextOverlay) return 'text';
    if (_selectedOverlayId != null) return 'selection';
    return 'default';
  }

  Widget _buildTopRow() {
    if (_isCropMode) {
      return Row(
        children: [
          // Blurred: the crop tool shows the media with no scrim over it,
          // so its controls sat straight on a busy frame and were hard to
          // pick out.
          StatusChromeButton(
            key: const Key('updates_media_crop_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleCropMode,
            blurred: true,
          ),
          const Spacer(),
          StatusChromeButton(
            key: const Key('updates_media_crop_done_button'),
            tooltip: 'Done',
            icon: Icons.check_rounded,
            onTap: _toggleCropMode,
            blurred: true,
          ),
        ],
      );
    }
    if (_isDrawMode) {
      return Row(
        children: [
          StatusChromeButton(
            key: const Key('updates_media_draw_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleDrawMode,
          ),
          const Spacer(),
          StatusChromeButtonGroup(
            children: [
              StatusChromeButton(
                key: const Key('updates_media_draw_undo_button'),
                tooltip: 'Undo stroke',
                icon: Icons.undo_rounded,
                onTap: _drawingStrokes.isNotEmpty ? _undoLastStroke : null,
                bare: true,
              ),
              StatusChromeButton(
                key: const Key('updates_media_draw_done_button'),
                tooltip: 'Done',
                icon: Icons.check_rounded,
                onTap: _toggleDrawMode,
                bare: true,
              ),
            ],
          ),
        ],
      );
    }
    if (_isBlurMode) {
      return Row(
        children: [
          StatusChromeButton(
            key: const Key('updates_media_blur_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleBlurMode,
          ),
          const Spacer(),
          StatusChromeButton(
            key: const Key('updates_media_blur_done_button'),
            tooltip: 'Done',
            icon: Icons.check_rounded,
            onTap: _toggleBlurMode,
          ),
        ],
      );
    }
    // A placed text overlay that's merely selected (e.g. mid-drag, see
    // _onOverlayScaleStart) but not actively being typed into shows no
    // special chrome at all -- falls straight through to the plain default
    // toolbar below, exactly as if nothing were selected. Only entering
    // real text editing (a tap on it, see _handleOverlayTap) brings back
    // this bar's alignment/decoration icons and the redesigned editing view.
    final showsTextEditingChrome =
        _selectedOverlay?.type == StatusMediaOverlayType.text &&
            _isEditingTextOverlay;
    if (_selectedOverlay != null &&
        (_selectedOverlay!.type != StatusMediaOverlayType.text ||
            showsTextEditingChrome)) {
      return _ComposerTopBar(
        selectedOverlay: _selectedOverlay,
        onClose: () => Navigator.of(context).maybePop(),
        onDoneEditing: () => _commitInlineTextEditing(clearSelection: true),
        onCycleAlignment: _cycleTextAlignment,
        onToggleBackground: _toggleTextBackground,
      );
    }
    return Row(
      // Close button on the leading edge, tool capsule on the trailing one.
      // A Spacer cannot do this: it is a flex child, so it and the capsule's
      // own Flexible split the free space between them, leaving the capsule
      // half the row wide with its tools clipped.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        StatusChromeButton(
          key: const Key('updates_media_close_composer_button'),
          tooltip: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        // Loose, not Expanded: the capsule sizes to its buttons rather than
        // to whatever width is left beside the close button.
        Flexible(
          fit: FlexFit.loose,
          child: _ComposerToolbar(
            onAddText: _addTextOverlay,
            hasMusic: _musicTrack != null,
            isTextSelected: false,
            onAddStickerOrEmoji: _openStickerAndEmojiPicker,
            onAddMusic: _openMusicPicker,
            onDraw: _toggleDrawMode,
            onBlur: _toggleBlurMode,
            onCropOrRotate: _toggleCropMode,
          ),
        ),
      ],
    );
  }

  /// A tool's own small tray, floating directly above the always-visible
  /// caption+send row -- null when nothing needs it (default toolbar
  /// state, and crop/draw, whose controls float over the media itself
  /// instead).
  /// The bottom tray, cross-faded on the shared timing so switching tools
  /// eases between trays instead of snapping a new one into place.
  Widget _buildAnimatedBottomTray(bool isTextSelected) {
    final tray = _buildBottomCenterTray(isTextSelected);
    return StatusModeSwitcher(
      alignment: Alignment.bottomCenter,
      child: KeyedSubtree(
        key: ValueKey('tray-$_activeToolModeKey'),
        child: tray == null
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.only(
                  bottom: _isEditingTextOverlay ? 0 : 10,
                ),
                child: tray,
              ),
      ),
    );
  }

  /// The media, cross-faded between the preview's framing and the crop
  /// tool's while the transition runs. See the call site for why the two
  /// cannot simply be swapped.
  Widget _buildComposerMediaLayer({required bool showFrameOutline}) {
    final transition = _cropTransition;

    Widget layer({required bool asCrop, required bool interactive}) {
      return _ComposerMediaLayer(
        type: widget.type,
        localMediaPath: widget.localMediaPath,
        mediaTransform: _mediaTransform,
        videoController: _videoController,
        videoInitialization: _videoInitialization,
        allowTransformGestures: interactive && _allowMediaTransformGestures,
        showFrameOutline: asCrop,
        cropResizeAnchorWindow: _cropProjectionAnchor,
        cropInsetFactor: transition,
        drawingStrokes: _displayedDrawingStrokes,
        onSourceSizeResolved: _adoptOriginalMediaFrameIfNeeded,
        onScaleStart: interactive ? _onMediaScaleStart : (_) {},
        onScaleUpdate: interactive ? _onMediaScaleUpdate : (_, __) {},
        onScaleEnd: interactive ? _onMediaScaleEnd : (_) {},
      );
    }

    // Settled at either end, only one framing exists -- so nothing is drawn
    // twice except during the transition itself.
    if (!showFrameOutline) {
      return layer(asCrop: false, interactive: true);
    }
    if (transition >= 1) {
      return layer(asCrop: true, interactive: true);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: (1 - transition).clamp(0.0, 1.0),
          // Never the gesture target: the crop framing on top owns input for
          // the whole transition, so a pinch cannot land on the copy that is
          // fading out.
          child: IgnorePointer(child: layer(asCrop: false, interactive: false)),
        ),
        Opacity(
          opacity: transition.clamp(0.0, 1.0),
          child: layer(asCrop: true, interactive: true),
        ),
      ],
    );
  }

  Widget? _buildBottomCenterTray(bool isTextSelected) {
    // Actively typing (keyboard up): WhatsApp's own layout -- a row of
    // tappable font-style swatches sits directly above the keyboard, and
    // the color rail (built separately, see _isEditingTextOverlay in
    // build()) floats on the right. Once editing ends, the overlay fully
    // deselects (see onDoneEditing) and this returns null like any other
    // unselected state -- no lingering quick-tools tray.
    if (isTextSelected && _isEditingTextOverlay) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Same size/weight controls the text status gets -- one shared
          // widget, so the two tools cannot drift apart.
          StatusTextSizeWeightControls(
            sliderKey: const Key('updates_media_text_size_slider'),
            weightButtonKey: const Key('updates_media_text_weight_button'),
            style: _activeTextStyle,
            onSizeChanged: (scale) => _updateSelectedTextStyle(
              (style) => style.copyWith(sizeScale: scale),
            ),
            onWeightChanged: (index) => _updateSelectedTextStyle(
              (style) => style.copyWith(fontWeightIndex: index),
            ),
          ),
          StatusTextFontStyleRow(
            rowKey: const Key('updates_media_text_font_row'),
            optionKeyBuilder: (fontId) =>
                Key('updates_media_text_font_option_$fontId'),
            selectedFontId: _activeTextStyle.fontId,
            onFontSelected: (fontId) {
              _updateSelectedTextStyle(
                (style) => style.copyWith(fontId: fontId),
              );
            },
          ),
        ],
      );
    }
    if (_selectedOverlay?.type == StatusMediaOverlayType.music) {
      return _ComposerMusicEditingTray(
        selectedStyleId: _selectedMusicStyleId,
        styleOptions: _musicBannerStyles,
        onSelectStyle: _updateSelectedMusicStyle,
      );
    }
    if (_isBlurMode) {
      return _BlurEditingTray(
        blurSigma: _mediaTransform.blurSigma,
        onChanged: _setBlurSigma,
      );
    }
    return null;
  }

  void _updateDeleteTargetHover({
    required Offset globalFocalPoint,
    required bool isDraggingOverlay,
  }) {
    final deleteContext = _deleteTargetKey.currentContext;
    if (!isDraggingOverlay || deleteContext == null) {
      if (_isDeleteTargetActive) {
        setState(() {
          _isDeleteTargetActive = false;
        });
      }
      return;
    }

    final box = deleteContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }

    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    final isHovering = rect.inflate(12).contains(globalFocalPoint);
    if (isHovering == _isDeleteTargetActive) {
      return;
    }
    setState(() {
      _isDeleteTargetActive = isHovering;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTextSelected =
        _selectedOverlay?.type == StatusMediaOverlayType.text;
    // Crop mode is the only case that still needs a frame boundary shown --
    // placing/dragging text, emoji, stickers etc. no longer shows any
    // border: WhatsApp doesn't show one either, it was inaccurate once
    // overlays became free to move across the whole frame, and it visually
    // doubled up with this same frame outline whenever both were active at
    // once (e.g. in crop mode).
    // Rendered for the whole transition, not just while the tool is
    // nominally open, so leaving it can animate out rather than vanish.
    final showPlacementGuide = _isCropMode || _cropModeController.value > 0;

    // Keep the whole canvas pinned in place when the keyboard opens (e.g.
    // editing a text overlay) -- WhatsApp's own text tool never moves or
    // shrinks the photo/video underneath, it just docks the keyboard over
    // the bottom of the screen. Scaffold's default `resizeToAvoidBottomInset`
    // instead shrinks this whole body by the keyboard's height, which was
    // squeezing the media layer's Positioned(top:.., bottom:..) box upward
    // every time text editing started. Only the caption/tool-tray row below
    // needs to react to the keyboard now, via MediaQuery.viewInsetsOf.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    // The media composer already lays a dark gradient across its top edge
    // for its own toolbar, so it needs the overlay style but no extra
    // status-bar scrim -- a second one would double-darken the photo.
    return StatusStorySystemChrome(
      child: Scaffold(
        key: const Key('updates_media_composer_screen'),
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed, exactly like the story viewer renders a posted
            // segment (SizedBox.expand around the same surface) -- so what
            // the composer previews *is* what gets posted, with the toolbar,
            // trim strip and caption row floating over it the way WhatsApp
            // does. Inset-ing the media here instead made every "Fit to
            // screen" preview a lie: it fit the media to a shorter box than
            // the screen it would actually fill once posted.
            // Mid-transition both framings are drawn and cross-faded.
            //
            // The two render paths do not meet: crop mode contain-fits the
            // media into the whole canvas and magnifies it with a matrix,
            // while the preview cover-fits it into the ratio'd frame and
            // magnifies it inside. Measured on an 0.8-ratio frame the two
            // disagree by 84pt in height even at zero rotation, so switching
            // between them in one frame is a visible jump however well the
            // frame inset itself is animated. Fading across the gap is
            // concealment, not a cure -- the geometries still disagree, and
            // making them agree means changing what offsetDx/offsetDy mean,
            // which every already-posted story is stored against.
            Positioned.fill(
              child: _buildComposerMediaLayer(
                showFrameOutline: showPlacementGuide,
              ),
            ),
            // Crop window corner handles -- a separate layer, in the exact
            // same canvas coordinate space as _ComposerMediaLayer above (both
            // full-bleed), so the handles land precisely on the crop window
            // StatusStoryMediaSurface draws inside that layer. Sits on top so
            // a drag starting on a handle's small hit target wins over the
            // whole-surface move gesture underneath; drags anywhere else fall
            // through to that layer untouched.
            if (_isCropMode)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = constraints.biggest;
                    _lastCropCanvasSize = canvasSize;
                    // Where the selection lands on screen once the media
                    // has been transformed under it -- which, mid corner
                    // drag, is a shrinking rect over a picture that is
                    // holding still.
                    final window = statusCropProjection(
                      canvasSize: canvasSize,
                      window: cropWindowRectFor(
                        _cropMediaBoundsFor(canvasSize),
                        statusCropRatioFor(
                          canvasSize,
                          _mediaTransform.frameAspectRatio,
                        ),
                        _mediaTransform.scale,
                        _mediaTransform.offsetDx,
                        _mediaTransform.offsetDy,
                      ),
                      anchorWindow: _cropProjectionAnchor,
                      ratio: _mediaTransform.frameAspectRatio,
                      insetFactor: _cropTransition,
                    ).screenWindow;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final corner in _CropCorner.values)
                          _CropCornerHandle(
                            key: Key(
                              'updates_media_crop_corner_${corner.name}',
                            ),
                            corner: corner,
                            // The true window corner -- _CropCornerHandle's
                            // own hit target is what stays reachable near the
                            // canvas edge, not this point, so the bracket
                            // always sits exactly on the window's border.
                            point: _cropWindowCornerPoint(corner, window),
                            onPanStart: () => _onCropCornerPanStart(
                              corner,
                              canvasSize,
                              _cropWindowCornerPoint(corner, window),
                            ),
                            onPanUpdate: (details) =>
                                _onCropCornerPanUpdate(details, canvasSize),
                            onPanEnd: _onCropCornerPanEnd,
                          ),
                      ],
                    );
                  },
                ),
              ),
            if (_isDrawMode)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = constraints.biggest;
                    return GestureDetector(
                      key: const Key('updates_media_draw_surface'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) =>
                          _handleDrawPanStart(details, canvasSize),
                      onPanUpdate: (details) =>
                          _handleDrawPanUpdate(details, canvasSize),
                      onPanEnd: _handleDrawPanEnd,
                    );
                  },
                ),
              ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(0x8A000000),
                      Colors.transparent,
                      Color(0xAA000000),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: <double>[0, 0.46, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onTap: _handleCanvasTap,
                behavior: HitTestBehavior.translucent,
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final availableSize = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              final frameSize = statusStoryFrameSizeFor(
                                availableSize,
                                _mediaTransform.frameAspectRatio,
                              );
                              return Center(
                                child: SizedBox(
                                  width: frameSize.width,
                                  height: frameSize.height,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    // Lets a dragged overlay keep tracking the
                                    // finger past the frame edge, all the way
                                    // down to the delete target below the
                                    // canvas -- Stack clips overflow by
                                    // default, which would otherwise make the
                                    // overlay vanish the moment it left the
                                    // photo instead of following the drag.
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Nothing placed on the media while
                                      // cropping. Long overlay text covers
                                      // the frame, which both hides what
                                      // is being cropped and gets in the
                                      // way of the corner handles. They
                                      // are all still there on Done.
                                      if (!_isCropMode)
                                        for (final item in _overlayItems)
                                          _InteractiveMediaOverlay(
                                            key: Key(
                                              'updates_overlay_item_${item.id}',
                                            ),
                                            item: item,
                                            canvasSize: frameSize,
                                            // No selection border while actively
                                            // typing -- matches WhatsApp, whose
                                            // text tool never shows a bounding
                                            // box that reads like a crop frame
                                            // around the text being edited.
                                            // Never for text. Its box is
                                            // clamped to the media frame,
                                            // so on text taller than the
                                            // frame -- which is the whole
                                            // point of letting it use the
                                            // screen -- the border landed
                                            // exactly on the frame edges
                                            // and read as a crop outline
                                            // rather than a selection.
                                            // Emoji, stickers and music
                                            // are small enough that the
                                            // box always hugs them, and
                                            // there it earns its keep.
                                            isSelected: item.type !=
                                                    StatusMediaOverlayType
                                                        .text &&
                                                _selectedOverlayId == item.id,
                                            allowTransformGestures:
                                                _editingTextOverlayId !=
                                                    item.id,
                                            // No onDoubleTap any more -- a
                                            // single tap on text now reopens
                                            // editing directly (see
                                            // _handleOverlayTap), so keeping a
                                            // double-tap handler around would
                                            // only make Flutter wait out the
                                            // double-tap window before firing
                                            // the single tap, adding a laggy
                                            // delay to something that should
                                            // feel instant.
                                            onTap: _editingTextOverlayId ==
                                                    item.id
                                                ? null
                                                : () => _handleOverlayTap(item),
                                            onScaleStart: (details) =>
                                                _onOverlayScaleStart(
                                              item,
                                              details,
                                            ),
                                            onScaleUpdate: (details) =>
                                                _onOverlayScaleUpdate(
                                              details,
                                              frameSize,
                                            ),
                                            onScaleEnd: _onOverlayScaleEnd,
                                            // The item being actively edited is
                                            // rendered by a dedicated, centered
                                            // widget below instead (see
                                            // _isEditingTextOverlay), decoupled
                                            // from its dragged position -- so it
                                            // stays put and legible above the
                                            // keyboard like WhatsApp's own text
                                            // tool, not wherever it was last
                                            // placed on the canvas.
                                            child: _editingTextOverlayId ==
                                                    item.id
                                                ? const SizedBox.shrink()
                                                : OverflowBox(
                                                    // Loosens the frame's own
                                                    // SizedBox, which would
                                                    // otherwise clamp text to
                                                    // the frame while the
                                                    // posted story lets it use
                                                    // the whole screen -- the
                                                    // preview has to be handed
                                                    // the same room or it lies
                                                    // about the result.
                                                    //
                                                    // fit: deferToChild is
                                                    // what makes this shrink
                                                    // to the text. The default
                                                    // fills, which drew the
                                                    // selection border around
                                                    // the whole canvas and let
                                                    // the overlay swallow taps
                                                    // everywhere;
                                                    // UnconstrainedBox
                                                    // shrink-wraps too but
                                                    // reports the overflow as
                                                    // a layout error, which
                                                    // long text legitimately
                                                    // causes here.
                                                    fit: OverflowBoxFit
                                                        .deferToChild,
                                                    alignment: Alignment.center,
                                                    maxWidth:
                                                        availableSize.width,
                                                    maxHeight:
                                                        availableSize.height,
                                                    child: StatusOverlayContent(
                                                      item: item,
                                                      compact: false,
                                                      accentColor:
                                                          AppPalette.emerald,
                                                      canvasSize: availableSize,
                                                    ),
                                                  ),
                                          ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // WhatsApp's own top chrome: close/tool icons always live
                  // here, with the video trim filmstrip and a mute toggle
                  // directly beneath -- never swapped out for a tool's own
                  // tray the way the bottom controls used to be, so the
                  // media's framing never has to jump when a tool opens.
                  Positioned(
                    top: 14,
                    left: 14,
                    right: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusModeSwitcher(
                          alignment: Alignment.topCenter,
                          child: KeyedSubtree(
                            key: ValueKey('top-row-$_activeToolModeKey'),
                            child: _buildTopRow(),
                          ),
                        ),
                        // Hidden while editing text or cropping, like
                        // WhatsApp -- the mute toggle and trim filmstrip
                        // aren't related to either tool, so they get out of
                        // the way instead of cluttering a focused editing view.
                        if (_isVideo &&
                            _videoFullDurationSeconds > 0 &&
                            !_isEditingTextOverlay &&
                            !_isCropMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: ValueListenableBuilder<double?>(
                              valueListenable: _videoPosition,
                              builder: (context, position, _) =>
                                  VideoTrimScrubber(
                                key: const Key('updates_media_trim_scrubber'),
                                videoPath: widget.localMediaPath,
                                fullDurationSeconds: _videoFullDurationSeconds,
                                trimStartSeconds: _trimStartSeconds,
                                trimEndSeconds:
                                    _trimStartSeconds + _durationSeconds,
                                minTrimSeconds: _minDurationSeconds,
                                maxTrimSeconds: _maxDurationSeconds,
                                onScrubStart: _handleTrimScrubStart,
                                onScrubUpdate: _handleTrimScrubUpdate,
                                onScrubEnd: _handleTrimScrubEnd,
                                positionSeconds: position,
                                // Mute rides inside the strip's own row, so
                                // the two read as one control group while
                                // the duration/size label stays above them
                                // on its own.
                                // No chrome of its own: it shares the
                                // strip's surface, so its own background
                                // would only read as a second control
                                // parked next to the filmstrip.
                                leading: _MuteToggle(
                                  key: const Key('updates_media_mute_button'),
                                  isMuted: _isMuted,
                                  onTap: _toggleMute,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // WhatsApp's own big center play/pause overlay -- only
                  // shown while paused, tapping it resumes playback. Hidden
                  // while editing text or cropping, unrelated to either tool.
                  if (_isVideo &&
                      !_isVideoPlaying &&
                      !_isEditingTextOverlay &&
                      !_isCropMode)
                    Positioned.fill(
                      child: Center(
                        child: _VideoPlayPauseOverlay(
                          onTap: _toggleVideoPlayback,
                        ),
                      ),
                    ),
                  // Actively editing text: the card being typed floats free
                  // of its dragged position, centered in whatever space is
                  // left between the top bar and the keyboard/font row --
                  // WhatsApp's own text tool always keeps it here while
                  // typing, and only lets you drag it once you're done (see
                  // the isSelected/allowTransformGestures overrides above).
                  if (_isEditingTextOverlay) ...[
                    Positioned(
                      top: _kTextEditTopClearance,
                      left: 0,
                      right: 0,
                      bottom: keyboardInset + _kTextEditBottomRowHeight,
                      child: Center(
                        child: StatusTextEditorCard(
                          cardKey:
                              const Key('updates_media_inline_text_editor'),
                          fieldKey:
                              const Key('updates_media_inline_text_field'),
                          controller: _inlineTextController,
                          focusNode: _inlineTextFocusNode,
                          textStyleModel: _activeTextStyle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: _kTextEditTopClearance,
                      right: 14,
                      bottom: keyboardInset + _kTextEditBottomRowHeight,
                      child: StatusTextColorRail(
                        railKey: const Key('updates_media_text_color_rail'),
                        barKey: const Key('updates_media_text_color_bar'),
                        thumbKey: const Key('updates_media_text_color_thumb'),
                        selectedColor:
                            _activeTextStyle.textColor ?? Colors.white,
                        onSelectColor: (color) {
                          _updateSelectedTextStyle(
                            (style) => style.copyWith(
                              textColorValue: color.toARGB32(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  // Crop mode's own floating controls, in the gap below the
                  // media's bottom edge -- matches WhatsApp's own crop screen:
                  // rotate at bottom-left, the ratio bubble at bottom-right,
                  // Reset centered above them once a pinch/pan has actually
                  // moved the media (the frame itself never resizes or
                  // moves -- only the media underneath a fixed-ratio frame
                  // does, so you can choose which part of it gets cropped).
                  if (_isCropMode) ...[
                    Positioned(
                      left: 14,
                      bottom: 74,
                      child: StatusChromeButton(
                        key: const Key('updates_media_rotate_button'),
                        tooltip: 'Rotate',
                        icon: Icons.rotate_90_degrees_cw_rounded,
                        onTap: _rotateMediaClockwise,
                        blurred: true,
                      ),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 74,
                      child: _CropRatioBubbleButton(
                        label: _currentCropRatioLabel,
                        options: _cropAspectOptions,
                        selectedRatio: _mediaTransform.frameAspectRatio,
                        isFitToScreen: _isFitToScreenCrop,
                        onSelectOption: _selectCropAspectOption,
                      ),
                    ),
                    // Straightening, right above the ratio/reset row --
                    // where WhatsApp puts it, and close enough to the media
                    // that the horizon and the dial are in one glance.
                    Positioned(
                      left: 24,
                      right: 24,
                      // Clear of the Reset pill on the row below -- the
                      // reading used to sit right on top of it.
                      bottom: 196,
                      child: RotationDial(
                        key: const Key('updates_media_rotation_dial'),
                        degrees: _mediaTransform.rotationDegrees,
                        onChanged: _setRotationDegrees,
                      ),
                    ),
                    if (_hasCropEdits)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 130,
                        child: Center(
                          // Same blurred surface as the crop tool's other
                          // controls -- a bare label on the media was the
                          // hardest of the lot to read.
                          child: StatusChromeSurface(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(999)),
                            blurred: true,
                            child: TextButton(
                              key: const Key('updates_media_crop_reset_button'),
                              onPressed: _resetMediaTransformOffset,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.transparent,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                              ),
                              child: const Text(
                                'Reset',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  // Draw mode's own floating controls -- a vertical color
                  // rail down the right side (matches WhatsApp's reference
                  // screenshot) and a small pill for eraser/stroke size
                  // centered above the always-visible caption row.
                  if (_isDrawMode) ...[
                    Positioned(
                      top: _mediaTopInset + 10,
                      right: 14,
                      bottom: _kMediaBottomInset + 10,
                      child: DrawColorRail(
                        keyPrefix: 'updates_media_draw',
                        selectedColor: _drawColor,
                        isEraserMode: _isEraserMode,
                        onSelectColor: (color) {
                          setState(() {
                            _drawColor = color;
                            _isEraserMode = false;
                          });
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 74,
                      child: Center(
                        child: DrawStrokeTray(
                          keyPrefix: 'updates_media_draw',
                          color: _drawColor,
                          isEraserMode: _isEraserMode,
                          onToggleEraser: () => setState(
                            () => _isEraserMode = !_isEraserMode,
                          ),
                          selectedStrokeIndex:
                              _drawStrokeWidths.indexOf(_drawStrokeWidth),
                          onSelectStroke: (index) => setState(
                            () => _drawStrokeWidth = _drawStrokeWidths[index],
                          ),
                        ),
                      ),
                    ),
                  ],
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: _kMediaBottomInset,
                    child: _selectedOverlay == null || _isEditingTextOverlay
                        ? const SizedBox.shrink()
                        : Center(
                            key: const Key('updates_media_delete_target_host'),
                            child: KeyedSubtree(
                              key: _deleteTargetKey,
                              child: IgnorePointer(
                                ignoring: !_isDraggingOverlay,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOutCubic,
                                  offset: _isDraggingOverlay
                                      ? Offset.zero
                                      : const Offset(0, 0.08),
                                  child: AnimatedOpacity(
                                    key: const Key(
                                      'updates_media_delete_overlay_visibility',
                                    ),
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    opacity: _isDraggingOverlay ? 1 : 0,
                                    child: StatusOverlayDeleteTarget(
                                      key: const Key(
                                        'updates_media_delete_overlay_button',
                                      ),
                                      isActive: _isDeleteTargetActive,
                                      onTap: () =>
                                          _removeOverlay(_selectedOverlay!.id),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  // Caption + send always live together in one row now --
                  // never hidden behind whichever tool is active, except
                  // while actively editing a text overlay or cropping: each
                  // of those is a focused, full-screen editing view with its
                  // own dedicated controls (WhatsApp's text tool shows only
                  // the keyboard below its font/color tray; the crop tool
                  // shows only rotate/ratio below the frame), so the caption
                  // field and share button step aside rather than floating
                  // over content unrelated to what the user is doing. A
                  // tool's own tray (text style options, music banner style,
                  // blur slider) floats directly above this row when relevant.
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14 + keyboardInset,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAnimatedBottomTray(isTextSelected),
                        // Draw is a focused editing view with its own
                        // controls, exactly like text and crop -- the
                        // caption and share step aside for it too.
                        if (!_isEditingTextOverlay &&
                            !_isCropMode &&
                            !_isDrawMode)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: StatusChromeCaptionField(
                                  fieldKey: const Key(
                                    'updates_media_caption_field',
                                  ),
                                  controller: _captionController,
                                ),
                              ),
                              const SizedBox(width: 12),
                              StatusChromeSendButton(
                                actionKey: const Key(
                                  'updates_share_media_status_button',
                                ),
                                onTap: _shareStatus,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerMediaLayer extends StatelessWidget {
  const _ComposerMediaLayer({
    required this.type,
    required this.localMediaPath,
    required this.mediaTransform,
    required this.allowTransformGestures,
    required this.showFrameOutline,
    required this.onSourceSizeResolved,
    this.cropResizeAnchorWindow,
    this.cropInsetFactor = 1,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    this.videoController,
    this.videoInitialization,
    this.drawingStrokes = const <StatusDrawingStroke>[],
  });

  final StatusStoryType type;
  final String localMediaPath;
  final StatusMediaTransform mediaTransform;
  final bool allowTransformGestures;
  final bool showFrameOutline;

  /// See [StatusStoryMediaSurface.cropResizeAnchorWindow].
  final Rect? cropResizeAnchorWindow;

  /// See [StatusStoryMediaSurface.cropInsetFactor].
  final double cropInsetFactor;
  final ValueChanged<Size> onSourceSizeResolved;
  final VideoPlayerController? videoController;
  final Future<void>? videoInitialization;
  final GestureScaleStartCallback onScaleStart;
  final void Function(ScaleUpdateDetails details, Size canvasSize)
      onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final List<StatusDrawingStroke> drawingStrokes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return StatusStoryMediaSurface(
          type: type,
          localMediaPath: localMediaPath,
          mediaTransform: mediaTransform,
          videoController: videoController,
          videoInitialization: videoInitialization,
          showFrameOutline: showFrameOutline,
          unavailableMessage: 'This media is no longer available.',
          drawingStrokes: drawingStrokes,
          cropResizeAnchorWindow: cropResizeAnchorWindow,
          cropInsetFactor: cropInsetFactor,
          onSourceSizeResolved: onSourceSizeResolved,
          onScaleStart: allowTransformGestures ? onScaleStart : null,
          onScaleUpdate: allowTransformGestures
              ? (details) => onScaleUpdate(details, constraints.biggest)
              : null,
          onScaleEnd: allowTransformGestures ? onScaleEnd : null,
        );
      },
    );
  }
}

class _InteractiveMediaOverlay extends StatelessWidget {
  const _InteractiveMediaOverlay({
    required this.item,
    required this.canvasSize,
    required this.isSelected,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.child,
    this.onTap,
    this.allowTransformGestures = true,
    super.key,
  });

  final StatusMediaOverlayItem item;
  final Size canvasSize;
  final bool isSelected;
  final Widget child;
  final VoidCallback? onTap;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final bool allowTransformGestures;

  @override
  Widget build(BuildContext context) {
    final offset = statusStoryOverlayOffsetFor(canvasSize, item);
    final shell = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(isSelected ? 6 : 2),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.76)
              : Colors.transparent,
          width: 1.1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );

    return Center(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: item.rotation,
          child: Transform.scale(
            scale: item.scale,
            child: allowTransformGestures || onTap != null
                ? GestureDetector(
                    onTap: onTap,
                    onScaleStart: allowTransformGestures ? onScaleStart : null,
                    onScaleUpdate:
                        allowTransformGestures ? onScaleUpdate : null,
                    onScaleEnd: allowTransformGestures ? onScaleEnd : null,
                    behavior: HitTestBehavior.translucent,
                    child: shell,
                  )
                : shell,
          ),
        ),
      ),
    );
  }
}

/// Shown while a text overlay is selected -- which, by the time this bar
/// renders (see the gating in _buildTopRow), only ever happens while it's
/// actively being typed into. There's no longer a "selected but not
/// editing" state for text to land in: once Done is tapped the overlay
/// fully deselects and this bar goes away entirely, back to the plain
/// default toolbar, matching WhatsApp.
class _ComposerTopBar extends StatelessWidget {
  const _ComposerTopBar({
    required this.selectedOverlay,
    required this.onClose,
    required this.onDoneEditing,
    required this.onCycleAlignment,
    required this.onToggleBackground,
  });

  final StatusMediaOverlayItem? selectedOverlay;
  final VoidCallback onClose;
  final VoidCallback onDoneEditing;
  final VoidCallback onCycleAlignment;
  final VoidCallback onToggleBackground;

  @override
  Widget build(BuildContext context) {
    final hasTextSelection =
        selectedOverlay?.type == StatusMediaOverlayType.text;

    return Row(
      children: [
        StatusChromeButton(
          key: const Key('updates_media_close_composer_button'),
          tooltip: 'Close',
          icon: Icons.close_rounded,
          onTap: onClose,
        ),
        const Spacer(),
        if (hasTextSelection)
          // Matches WhatsApp's own text tool: alignment and background/
          // decoration toggles live in the top bar right next to Done --
          // and in one capsule, like the tool toolbar, rather than three
          // separate backgrounds sitting side by side.
          StatusChromeButtonGroup(
            children: [
              StatusChromeButton(
                key: const Key('updates_media_text_align_button'),
                tooltip: 'Text alignment',
                icon: Icons.format_align_center_rounded,
                onTap: onCycleAlignment,
                bare: true,
              ),
              StatusChromeButton(
                key: const Key('updates_media_text_decoration_button'),
                tooltip: 'Text background',
                icon: Icons.format_color_text_rounded,
                onTap: onToggleBackground,
                bare: true,
              ),
              StatusChromeButton(
                key: const Key('updates_media_text_done_button'),
                tooltip: 'Done editing',
                icon: Icons.check_rounded,
                onTap: onDoneEditing,
                bare: true,
              ),
            ],
          ),
      ],
    );
  }
}

class _ComposerMusicEditingTray extends StatelessWidget {
  const _ComposerMusicEditingTray({
    required this.selectedStyleId,
    required this.styleOptions,
    required this.onSelectStyle,
  });

  final String selectedStyleId;
  final List<_MusicBannerStyleOption> styleOptions;
  final ValueChanged<String> onSelectStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('updates_media_music_editing_tray'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: styleOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = styleOptions[index];
                final isSelected = option.id == selectedStyleId;
                return _MiniOptionChip(
                  selected: isSelected,
                  onTap: () => onSelectStyle(option.id),
                  icon: option.icon,
                  label: option.label,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The vertical color rail shown down the right side of the media while
/// drawing -- matches WhatsApp's own draw screen, which keeps color
/// selection as a tall strip beside the canvas rather than a horizontal
/// tray. Tapping the rainbow swatch reveals a vertical hue bar in its
/// place; the back arrow brings the swatches back.
/// WhatsApp's own draw tool is one continuous color bar, not a column of
/// preset swatches plus a separate "custom color" toggle -- the swatches
/// took real vertical space and the two-step reveal was an extra tap for
/// what should be a single drag. White sits at the top, black at the
/// bottom, the hue spectrum runs between them, and a drag/tap anywhere
/// picks the color straight off the bar.
class _BlurEditingTray extends StatelessWidget {
  const _BlurEditingTray({
    required this.blurSigma,
    required this.onChanged,
  });

  final double blurSigma;
  final ValueChanged<double> onChanged;

  static const double _maxBlurSigma = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('updates_media_blur_editing_tray'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.blur_on_rounded, color: Colors.white, size: 18),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                key: const Key('updates_media_blur_slider'),
                value: blurSigma.clamp(0, _maxBlurSigma),
                min: 0,
                max: _maxBlurSigma,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One draggable L-bracket corner handle on the crop window -- a 44x44
/// tap target (the platform's minimum touch size) centered on the
/// window's actual corner point, with a smaller painted bracket so the
/// visual mark stays crisp without ballooning the crop window's apparent
/// border. Dragging resizes the window from this corner; the opposite
/// corner stays fixed, matching WhatsApp's own free-form crop handles.
class _CropCornerHandle extends StatelessWidget {
  const _CropCornerHandle({
    required this.corner,
    required this.point,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    super.key,
  });

  // The hit target is asymmetric on purpose: it extends mostly *inward*
  // (toward the window's interior) from the true corner point, with just
  // a small margin *outward* past it. That keeps the tap target reachable
  // even when the corner sits right at the canvas edge (e.g. the
  // full-canvas default crop) -- without ever moving the bracket itself
  // off the window's actual corner, which is what made the bracket look
  // detached from the border it's supposed to mark.
  static const double _outwardMargin = 10;
  static const double _inwardMargin = 36;
  static const double _hitSize = _outwardMargin + _inwardMargin;
  static const double _visualSize = 26;

  final _CropCorner corner;
  final Offset point;
  final VoidCallback onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final ValueChanged<DragEndDetails> onPanEnd;

  bool get _isLeft =>
      corner == _CropCorner.topLeft || corner == _CropCorner.bottomLeft;
  bool get _isTop =>
      corner == _CropCorner.topLeft || corner == _CropCorner.topRight;

  @override
  Widget build(BuildContext context) {
    final outwardX = _isLeft ? _outwardMargin : _inwardMargin;
    final outwardY = _isTop ? _outwardMargin : _inwardMargin;

    return Positioned(
      left: point.dx - outwardX,
      top: point.dy - outwardY,
      width: _hitSize,
      height: _hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The true corner point, in this box's own local coordinates
            // -- exactly where the hit box's origin was offset from above.
            Positioned(
              left: outwardX - _visualSize / 2,
              top: outwardY - _visualSize / 2,
              width: _visualSize,
              height: _visualSize,
              child: CustomPaint(
                painter: _CropCornerBracketPainter(corner),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropCornerBracketPainter extends CustomPainter {
  const _CropCornerBracketPainter(this.corner);

  final _CropCorner corner;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final leg = size.width / 2;
    final dx = corner == _CropCorner.topLeft || corner == _CropCorner.bottomLeft
        ? leg
        : -leg;
    final dy = corner == _CropCorner.topLeft || corner == _CropCorner.topRight
        ? leg
        : -leg;
    canvas.drawLine(center, center + Offset(dx, 0), paint);
    canvas.drawLine(center, center + Offset(0, dy), paint);
  }

  @override
  bool shouldRepaint(covariant _CropCornerBracketPainter oldDelegate) =>
      oldDelegate.corner != corner;
}

/// The floating ratio button shown at the bottom-right of the media while
/// cropping -- tapping it opens a small liquid-glass bubble anchored right
/// above the button, matching WhatsApp's own compact ratio picker instead
/// of a full-height modal sheet or Material's default popup-menu chrome.
class _CropRatioBubbleButton extends StatelessWidget {
  const _CropRatioBubbleButton({
    required this.label,
    required this.options,
    required this.selectedRatio,
    required this.isFitToScreen,
    required this.onSelectOption,
  });

  final String label;
  final List<_CropAspectOption> options;
  final double? selectedRatio;

  /// Disambiguates the two options that both leave [selectedRatio] null --
  /// see the field of the same purpose on the composer's state.
  final bool isFitToScreen;
  final ValueChanged<_CropAspectOption> onSelectOption;

  bool _isOptionSelected(_CropAspectOption option) {
    if (selectedRatio == null) {
      if (option.isOriginal) {
        return !isFitToScreen;
      }
      return option.ratio == null && isFitToScreen;
    }
    return option.ratio != null &&
        (option.ratio! - selectedRatio!).abs() < 0.001;
  }

  Future<void> _openBubble(BuildContext buttonContext) async {
    final picked = await showLiquidGlassBubbleMenu<_CropAspectOption>(
      anchorContext: buttonContext,
      itemBuilder: (context) => [
        for (final option in options)
          LiquidGlassBubbleItem(
            key: Key('updates_media_crop_aspect_${option.label}'),
            label: option.label,
            selected: _isOptionSelected(option),
            onTap: () => Navigator.of(context).pop(option),
          ),
      ],
    );
    if (picked != null) {
      onSelectOption(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => GestureDetector(
        key: const Key('updates_media_crop_aspect_ratio_button'),
        onTap: () => _openBubble(buttonContext),
        // Blurred, like the rest of the crop tool's chrome: nothing sits
        // between these controls and the media.
        child: StatusChromeSurface(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          blurred: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.crop_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.hasMusic,
    required this.isTextSelected,
    required this.onAddText,
    required this.onAddStickerOrEmoji,
    required this.onAddMusic,
    required this.onDraw,
    required this.onBlur,
    required this.onCropOrRotate,
  });

  final bool hasMusic;
  final bool isTextSelected;
  final VoidCallback onAddText;
  final VoidCallback onAddStickerOrEmoji;
  final VoidCallback onAddMusic;
  final VoidCallback onDraw;
  final VoidCallback onBlur;
  final VoidCallback onCropOrRotate;

  @override
  Widget build(BuildContext context) {
    // The capsule this whole family of controls is matched to.
    return StatusChromeSurface(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _ToolbarRow(
        children: [
          // Order matches WhatsApp's own photo/video status editor:
          // text, stickers & emoji (one combined tool), draw, music,
          // blur, crop/rotate.
          _ToolbarToolButton(
            key: const Key('updates_media_panel_fonts'),
            tooltip: isTextSelected ? 'Edit text' : 'Add text',
            icon: isTextSelected
                ? Icons.edit_outlined
                : Icons.text_fields_rounded,
            onTap: onAddText,
            isActive: isTextSelected,
            expand: false,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_add_emoji_button'),
            tooltip: 'Stickers & emoji',
            icon: Icons.emoji_emotions_outlined,
            onTap: onAddStickerOrEmoji,
            expand: false,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_draw_button'),
            tooltip: 'Draw',
            icon: Icons.edit_note_rounded,
            onTap: onDraw,
            expand: false,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_add_music_button'),
            tooltip: hasMusic ? 'Change music' : 'Add music',
            icon:
                hasMusic ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
            onTap: onAddMusic,
            isActive: hasMusic,
            expand: false,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_blur_button'),
            tooltip: 'Blur',
            icon: Icons.blur_on_rounded,
            onTap: onBlur,
            expand: false,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_crop_rotate_button'),
            tooltip: 'Crop or rotate',
            icon: Icons.crop_rotate_rounded,
            onTap: onCropOrRotate,
            expand: false,
          ),
        ],
      ),
    );
  }
}

/// Lays the tool buttons out so the capsule hugs them.
///
/// The capsule is handed the whole width left over beside the close button,
/// and a plain Row inside it stretches to fill that -- which left a bite of
/// empty capsule after the last tool. Sizing to the buttons keeps the
/// capsule tight to its contents, and it only becomes scrollable on a screen
/// too narrow to hold them all.
class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({required this.children});

  /// 42pt button plus its 2pt margins either side.
  static const double _buttonExtent = 46;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final row = Row(mainAxisSize: MainAxisSize.min, children: children);
        if (children.length * _buttonExtent <= constraints.maxWidth) {
          return row;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: row,
        );
      },
    );
  }
}

class _ToolbarToolButton extends StatelessWidget {
  const _ToolbarToolButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.expand = true,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // No spreading ink. These sit directly on the media, so a ripple
        // washes across the picture -- and tapping crop leaves one running
        // as the screen changes underneath it. A contained highlight gives
        // the same acknowledgement without painting over the photo.
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.white.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 42,
          width: expand ? null : 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );

    if (!expand) {
      return button;
    }

    return Expanded(child: button);
  }
}

/// The big play button WhatsApp overlays centered on a paused video status
/// -- a light glass circle with a dark play glyph, distinct from the dark
/// glass chrome used everywhere else on this screen since it sits directly
/// on the video content, not floating above it.
class _VideoPlayPauseOverlay extends StatelessWidget {
  const _VideoPlayPauseOverlay({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        key: const Key('updates_media_video_play_pause_overlay'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        canRequestFocus: false,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.black87,
            size: 40,
          ),
        ),
      ),
    );
  }
}

/// A plain "Add a caption..." field -- WhatsApp/Instagram's simple caption
/// input, distinct from the rich draggable text tool. Multi-line since a
/// caption (unlike a single styled text overlay) is expected to wrap.
class _MuteToggle extends StatelessWidget {
  const _MuteToggle({required this.isMuted, required this.onTap, super.key});

  final bool isMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isMuted ? 'Unmute' : 'Mute',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            // Full 44pt wide, but only as tall as the filmstrip it sits
            // beside. The two share one translucent surface, and that
            // surface is sized by its tallest child -- leaving this at 44
            // against a 40pt strip would band the capsule above and below
            // the strip, showing the media through exactly the way the
            // trim view used to.
            //
            // 40 rather than 44 keeps the tap target 4pt under the minimum
            // in docs/ui_layout_guidelines.md rule 7. Deliberate, and
            // called out rather than quietly relitigated: the alternative
            // is a capsule that cannot get shorter than 44 at all.
            width: 44,
            height: 40,
            child: Icon(
              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniOptionChip extends StatelessWidget {
  const _MiniOptionChip({
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  }) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.74)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: icon != null && label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Center(
                child: icon != null
                    ? Icon(
                        icon,
                        size: 17,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      )
                    : Text(
                        label!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
      ),
    );
  }
}

/// One combined sheet for both stickers and emoji -- matching WhatsApp's
/// own "Add yours" picker, which shows stickers first and emoji below it
/// in a single scroll, not two separate tools/sheets.
class _StickerAndEmojiPickerSheet extends StatefulWidget {
  const _StickerAndEmojiPickerSheet({required this.stickerPresets});

  final List<_StickerPreset> stickerPresets;

  @override
  State<_StickerAndEmojiPickerSheet> createState() =>
      _StickerAndEmojiPickerSheetState();
}

class _StickerAndEmojiPickerSheetState
    extends State<_StickerAndEmojiPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final visibleStickers = query.isEmpty
        ? widget.stickerPresets
        : widget.stickerPresets
            .where((preset) => preset.label.toLowerCase().contains(query))
            .toList(growable: false);

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Padding(
        // See the music sheet: the inset belongs on the scrolling content,
        // not on the sheet, or the whole grid floats above a band of glass.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('updates_media_sticker_search_field'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search stickers',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.52),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                key: const Key('updates_media_sticker_emoji_list'),
                padding: EdgeInsets.only(bottom: bottomInset + 12),
                children: [
                  Text(
                    'Stickers',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (visibleStickers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No stickers match that search.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final preset in visibleStickers)
                          InkWell(
                            key: Key(
                              'updates_media_sticker_option_'
                              '${widget.stickerPresets.indexOf(preset)}',
                            ),
                            onTap: () => Navigator.of(context).pop(preset),
                            borderRadius: BorderRadius.circular(999),
                            child: StatusOverlayContent(
                              item: StatusMediaOverlayItem(
                                id: 'sticker-preview-${preset.id}',
                                type: StatusMediaOverlayType.sticker,
                                label: preset.label,
                                accentColorValue: preset.accentColorValue,
                                secondaryColorValue: preset.secondaryColorValue,
                                variantId: preset.id,
                              ),
                              compact: true,
                              accentColor: Color(preset.accentColorValue),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'Emoji',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...buildStatusEmojiCategories(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicPickerSheet extends StatelessWidget {
  const _MusicPickerSheet({
    required this.tracks,
    required this.selectedTrackId,
    required this.previewingTrackId,
    required this.onPlayPreview,
  });

  final List<StatusMusicTrack> tracks;
  final String? selectedTrackId;
  final String? previewingTrackId;
  final ValueChanged<StatusMusicTrack> onPlayPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.68,
      child: Padding(
        // No bottom inset here: padding the sheet itself pushed the whole
        // list up and left a band of empty glass under it. The inset goes on
        // the scrolling content below, so rows run to the screen edge and
        // the last one can still scroll clear of the home indicator.
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.only(bottom: bottomInset + 12),
                itemCount: tracks.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.18,
                  ),
                ),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final isSelected = selectedTrackId == track.id;
                  final isPreviewing = previewingTrackId == track.id;
                  return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: Key('updates_media_music_option_$index'),
                        onTap: () => Navigator.of(context).pop(track),
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              _MusicArtBadge(track: track),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      // Regular weight: a list of a dozen
                                      // titles at w800 reads as a wall of
                                      // bold rather than a list.
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.64),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // The app's own glass button rather than a
                              // Material IconButton, so the sheet's controls
                              // read as the same family as everything else.
                              LiquidGlassIconButton(
                                actionKey: Key(
                                  'updates_media_music_play_button_$index',
                                ),
                                icon: isPreviewing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                tooltip: isPreviewing ? 'Pause' : 'Play',
                                onTap: () => onPlayPreview(track),
                                // visualSize, not size: size floors to a
                                // 48pt tap target, so the button drew at 48
                                // whatever was passed.
                                visualSize: 34,
                                iconSize: 17,
                                selected: isPreviewing,
                                iconColor: isPreviewing
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicArtBadge extends StatelessWidget {
  const _MusicArtBadge({
    required this.track,
  });

  final StatusMusicTrack track;

  @override
  Widget build(BuildContext context) {
    final primaryColor = track.color ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: primaryColor.withValues(alpha: 0.14),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: primaryColor,
          size: 20,
        ),
      ),
    );
  }
}
