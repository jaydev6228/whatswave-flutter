import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../data/status_music_repository.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/status_story_media_surface.dart';
import 'widgets/text_status_canvas.dart';
import 'widgets/video_trim_scrubber.dart';

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

class _MediaStatusComposerScreenState extends State<MediaStatusComposerScreen> {
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

  /// Set only while a corner is being actively dragged in the free-form
  /// crop grid -- tracks the literal on-screen size the user dragged to,
  /// so the frame follows the finger 1:1 instead of being re-fit to the
  /// largest rectangle of the resulting ratio (which is what made small
  /// drags appear to snap the media bigger). Cleared by anything that
  /// picks an explicit ratio some other way (a preset, Original, Fit to
  /// screen, or rotating), since those are meant to re-maximize within the
  /// canvas.
  Size? _customCropFrameSize;

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
  bool _wasPlayingBeforeTrimScrub = false;

  StatusMediaOverlayItem? _gestureAnchorOverlay;
  Offset? _gestureStartFocalPoint;
  StatusMediaTransform? _mediaGestureAnchorTransform;
  Offset? _mediaGestureStartFocalPoint;

  int _nextOverlaySeed = 0;

  bool get _isVideo => widget.type == StatusStoryType.video;
  bool get _isEditingTextOverlay => _editingTextOverlayId != null;
  // Repositioning/zooming the photo or video itself is only available
  // inside the crop tool -- matching WhatsApp exactly, where you can't pan
  // or pinch the media at all outside of that explicit step. Previously
  // this was allowed any time nothing else was selected, which is what let
  // the media drift around during ordinary editing.
  bool get _allowMediaTransformGestures =>
      _isCropMode &&
      !_isEditingTextOverlay &&
      _selectedOverlayId == null &&
      _gestureAnchorOverlay == null &&
      !_isDraggingOverlay &&
      !_isDrawMode;

  double get _minDurationSeconds => _isVideo ? 3 : 4;

  double get _maxDurationSeconds {
    final videoSeconds = _videoController?.value.duration.inSeconds ?? 0;
    final safeVideoMax = math.max(videoSeconds.toDouble(), 15);
    return _isVideo ? safeVideoMax.clamp(15, 30).toDouble() : 15.0;
  }

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
      (_videoController?.value.duration.inMilliseconds ?? 0) / 1000;

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
    _overlayGuideTimer?.cancel();
    _inlineTextController
      ..removeListener(_handleInlineTextChanged)
      ..dispose();
    _inlineTextFocusNode.dispose();
    _captionController.dispose();
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
        _durationSeconds = controller.value.duration.inSeconds
            .clamp(_minDurationSeconds.round(), _maxDurationSeconds.round())
            .toDouble();
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
    final trimEnd = _trimStartSeconds + _durationSeconds;
    final positionSeconds = controller.value.position.inMilliseconds / 1000;
    if (positionSeconds >= trimEnd) {
      unawaited(
        controller.seekTo(Duration(milliseconds: _trimStartMillis)),
      );
    }
  }

  /// A music track always overrides the video's own audio, same as the
  /// posted story's own playback logic -- muting is only meaningful when
  /// no music is layered on top.
  double get _effectiveVideoVolume =>
      (_isMuted || _musicTrack != null) ? 0 : 1;

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
        final fontScale = style.sizeScale.clamp(0.72, 1.28);
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
      _commitInlineTextEditing(clearSelection: false);
    }
    if (_selectedOverlayId == item.id &&
        item.type == StatusMediaOverlayType.text &&
        !_isEditingTextOverlay) {
      _beginInlineTextEditing(item);
      return;
    }
    _selectOverlay(item.id);
    if (item.type != StatusMediaOverlayType.text) {
      _scheduleOverlayGuideHide();
    }
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
    final position = _suggestedNormalizedPosition(baseDx: 0.5, baseDy: 0.76);
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

  void _editSelectedTextOverlay() {
    final selectedOverlay = _selectedOverlay;
    if (selectedOverlay == null ||
        selectedOverlay.type != StatusMediaOverlayType.text) {
      return;
    }
    _beginInlineTextEditing(selectedOverlay);
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
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<Object>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
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
    final selectedTrack = await showModalBottomSheet<StatusMusicTrack?>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
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
      return;
    }

    final position = _suggestedNormalizedPosition(baseDx: 0.24, baseDy: 0.16);
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

    final frameSize = _mediaFrameSizeFor(canvasSize);
    final delta = details.focalPoint - startFocalPoint;
    setState(() {
      _mediaTransform = anchorTransform.copyWith(
        scale: (anchorTransform.scale * details.scale).clamp(0.8, 4.0),
        offsetDx: (anchorTransform.offsetDx + (delta.dx / frameSize.width))
            .clamp(-1.6, 1.6)
            .toDouble(),
        offsetDy: (anchorTransform.offsetDy + (delta.dy / frameSize.height))
            .clamp(-1.6, 1.6)
            .toDouble(),
      );
    });
  }

  void _onMediaScaleEnd(ScaleEndDetails details) {
    _resetMediaGestureState();
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
      _customCropFrameSize = null;
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

  void _toggleCropMode() {
    setState(() {
      _isCropMode = !_isCropMode;
      if (!_isCropMode) {
        // Leaving crop mode settles the frame onto the standard
        // ratio-maximized sizing that the rest of the app (and the posted
        // story) uses -- the literal dragged size only makes sense as a
        // live drag aid tied to this exact on-screen canvas.
        _customCropFrameSize = null;
      }
    });
  }

  void _selectCropAspectOption(_CropAspectOption option) {
    setState(() {
      _customCropFrameSize = null;
      if (option.isOriginal) {
        _isFitToScreenCrop = false;
        final original = _effectiveOriginalAspectRatio;
        _mediaTransform = _mediaTransform.copyWith(
          frameAspectRatio: original,
          clearFrameAspectRatio: original == null,
        );
      } else if (option.ratio == null) {
        // Fit to screen -- no fixed shape at all, fills the available space.
        _isFitToScreenCrop = true;
        _mediaTransform = _mediaTransform.copyWith(clearFrameAspectRatio: true);
      } else {
        _isFitToScreenCrop = false;
        _mediaTransform =
            _mediaTransform.copyWith(frameAspectRatio: option.ratio);
      }
    });
  }

  /// Drags a corner of the crop frame to reshape it to any ratio, tracking
  /// the finger 1:1 like WhatsApp's own free-form crop grid (dragging a
  /// corner by 20px changes that edge by 20px, not 40 -- doubling the
  /// delta to keep the frame centered made every drag feel like it was
  /// moving twice as fast as the finger, and made it hard to predict which
  /// direction would grow vs. shrink the shape once it got small).
  void _resizeCropFrameByCorner(
    _CropCorner corner,
    Offset delta,
    Size canvasSize,
  ) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }
    // Continue from the literal size the last drag update landed on, not a
    // freshly re-fit "largest rectangle of this ratio" -- re-deriving from
    // the ratio each update is what let the frame balloon back up mid-drag
    // instead of tracking the finger.
    final currentFrameSize = _customCropFrameSize ??
        statusStoryFrameSizeFor(
          canvasSize,
          _mediaTransform.frameAspectRatio ??
              (canvasSize.width / canvasSize.height),
        );

    final isRight = corner == _CropCorner.topRight ||
        corner == _CropCorner.bottomRight;
    final isBottom = corner == _CropCorner.bottomLeft ||
        corner == _CropCorner.bottomRight;
    final dx = isRight ? delta.dx : -delta.dx;
    final dy = isBottom ? delta.dy : -delta.dy;

    const minSize = 110.0;
    final newWidth =
        (currentFrameSize.width + dx).clamp(minSize, canvasSize.width);
    final newHeight =
        (currentFrameSize.height + dy).clamp(minSize, canvasSize.height);

    setState(() {
      _isFitToScreenCrop = false;
      _customCropFrameSize = Size(newWidth, newHeight);
      _mediaTransform =
          _mediaTransform.copyWith(frameAspectRatio: newWidth / newHeight);
    });
  }

  /// Undoes any pinch/pan repositioning made while in the crop tool --
  /// matches the "Reset" action in WhatsApp's own crop screen. Leaves
  /// rotation and the selected aspect ratio alone; those are separate,
  /// deliberate choices with their own controls, not drift to undo.
  void _resetMediaTransformOffset() {
    setState(() {
      _mediaTransform = _mediaTransform.copyWith(
        scale: 1,
        offsetDx: 0,
        offsetDy: 0,
      );
    });
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
  Widget _buildTopRow() {
    if (_isCropMode) {
      return Row(
        children: [
          _GlassCircleButton(
            key: const Key('updates_media_crop_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleCropMode,
            showBorder: false,
          ),
          const Spacer(),
          _GlassCircleButton(
            key: const Key('updates_media_crop_done_button'),
            tooltip: 'Done',
            icon: Icons.check_rounded,
            onTap: _toggleCropMode,
          ),
        ],
      );
    }
    if (_isDrawMode) {
      return Row(
        children: [
          _GlassCircleButton(
            key: const Key('updates_media_draw_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleDrawMode,
            showBorder: false,
          ),
          const Spacer(),
          IconButton(
            key: const Key('updates_media_draw_undo_button'),
            tooltip: 'Undo stroke',
            onPressed: _drawingStrokes.isNotEmpty ? _undoLastStroke : null,
            icon: Icon(
              Icons.undo_rounded,
              color: _drawingStrokes.isNotEmpty
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.32),
            ),
          ),
          _GlassCircleButton(
            key: const Key('updates_media_draw_done_button'),
            tooltip: 'Done',
            icon: Icons.check_rounded,
            onTap: _toggleDrawMode,
          ),
        ],
      );
    }
    if (_isBlurMode) {
      return Row(
        children: [
          _GlassCircleButton(
            key: const Key('updates_media_blur_cancel_button'),
            tooltip: 'Cancel',
            icon: Icons.close_rounded,
            onTap: _toggleBlurMode,
            showBorder: false,
          ),
          const Spacer(),
          _GlassCircleButton(
            key: const Key('updates_media_blur_done_button'),
            tooltip: 'Done',
            icon: Icons.check_rounded,
            onTap: _toggleBlurMode,
          ),
        ],
      );
    }
    if (_selectedOverlay != null) {
      return _ComposerTopBar(
        selectedOverlay: _selectedOverlay,
        isEditingText: _isEditingTextOverlay,
        onClose: () => Navigator.of(context).maybePop(),
        onEditText: _editSelectedTextOverlay,
        onDoneEditing: () => _commitInlineTextEditing(clearSelection: false),
      );
    }
    return Row(
      children: [
        _GlassCircleButton(
          key: const Key('updates_media_close_composer_button'),
          tooltip: 'Close',
          icon: Icons.close_rounded,
          onTap: () => Navigator.of(context).maybePop(),
          showBorder: false,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ComposerToolbar(
            hasMusic: _musicTrack != null,
            isTextSelected: false,
            onAddText: _addTextOverlay,
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
  Widget? _buildBottomCenterTray(bool isTextSelected) {
    if (isTextSelected) {
      return _ComposerTextEditingTray(
        textStyleModel: _activeTextStyle,
        onAddText: _selectedOverlay?.type == StatusMediaOverlayType.text
            ? _editSelectedTextOverlay
            : _addTextOverlay,
        onFontSelected: (fontId) {
          _updateSelectedTextStyle(
            (style) => style.copyWith(fontId: fontId),
          );
        },
        onToneSelected: (colorValue) {
          _updateSelectedTextStyle(
            (style) => style.copyWith(
              textColorValue: colorValue,
              clearTextColor: colorValue == null,
            ),
          );
        },
        onToggleBackground: () {
          _updateSelectedTextStyle((style) {
            final nextSelected = !style.useSolidBackground;
            return style.copyWith(
              useSolidBackground: nextSelected,
              backgroundColorValue:
                  nextSelected ? (style.backgroundColorValue ?? 0xCC101418) : null,
              clearBackgroundColor: !nextSelected,
            );
          });
        },
        onCycleAlignment: () {
          _updateSelectedTextStyle((style) {
            final nextAlignment = switch (style.alignment) {
              StatusTextAlignment.left => StatusTextAlignment.center,
              StatusTextAlignment.center => StatusTextAlignment.right,
              StatusTextAlignment.right => StatusTextAlignment.left,
            };
            return style.copyWith(alignment: nextAlignment);
          });
        },
      );
    }
    if (_selectedOverlay?.type == StatusMediaOverlayType.music) {
      return _ComposerMusicEditingTray(
        onAddText: _addTextOverlay,
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
    final showPlacementGuide = _isCropMode;

    return Scaffold(
      key: const Key('updates_media_composer_screen'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: _mediaTopInset,
            bottom: _kMediaBottomInset,
            left: 0,
            right: 0,
            child: _ComposerMediaLayer(
              type: widget.type,
              localMediaPath: widget.localMediaPath,
              mediaTransform: _mediaTransform,
              videoController: _videoController,
              videoInitialization: _videoInitialization,
              allowTransformGestures: _allowMediaTransformGestures,
              showFrameOutline: showPlacementGuide,
              drawingStrokes: _displayedDrawingStrokes,
              frameSizeOverride: _isCropMode ? _customCropFrameSize : null,
              onSourceSizeResolved: _adoptOriginalMediaFrameIfNeeded,
              onScaleStart: _onMediaScaleStart,
              onScaleUpdate: _onMediaScaleUpdate,
              onScaleEnd: _onMediaScaleEnd,
            ),
          ),
          // WhatsApp's own crop screen: a 3x3 grid with draggable corner
          // handles lets you shape the frame to any custom ratio, not just
          // the presets in the list below. Inset the same way as the media
          // layer above (and by the same exact amount, so the grid lines up
          // with the frame pixel-for-pixel) -- letting either fill the raw
          // full screen during crop mode would put the bottom corner
          // handles right behind the crop tray, unreachable.
          if (_isCropMode)
            Positioned(
              top: _mediaTopInset,
              bottom: _kMediaBottomInset,
              left: 0,
              right: 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = constraints.biggest;
                  final frameSize = _customCropFrameSize ??
                      statusStoryFrameSizeFor(
                        canvasSize,
                        _mediaTransform.frameAspectRatio,
                      );
                  return Center(
                    child: _FreeformCropGrid(
                      frameSize: frameSize,
                      onCornerPanUpdate: (corner, delta) =>
                          _resizeCropFrameByCorner(corner, delta, canvasSize),
                    ),
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
                                    for (final item in _overlayItems)
                                      _InteractiveMediaOverlay(
                                        key: Key(
                                          'updates_overlay_item_${item.id}',
                                        ),
                                        item: item,
                                        canvasSize: frameSize,
                                        isSelected:
                                            _selectedOverlayId == item.id,
                                        allowTransformGestures:
                                            _editingTextOverlayId != item.id,
                                        onTap: _editingTextOverlayId == item.id
                                            ? null
                                            : () => _handleOverlayTap(item),
                                        onDoubleTap: _editingTextOverlayId ==
                                                    item.id ||
                                                item.type !=
                                                    StatusMediaOverlayType.text
                                            ? null
                                            : _editSelectedTextOverlay,
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
                                        child: _editingTextOverlayId == item.id
                                            ? _EditableTextOverlayCard(
                                                controller:
                                                    _inlineTextController,
                                                focusNode: _inlineTextFocusNode,
                                                textStyleModel: item
                                                        .textStyle ??
                                                    _defaultTextOverlayStyle,
                                              )
                                            : StatusOverlayContent(
                                                item: item,
                                                compact: false,
                                                accentColor: AppPalette.emerald,
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
                      _buildTopRow(),
                      if (_isVideo && _videoFullDurationSeconds > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _GlassCircleButton(
                                key: const Key('updates_media_mute_button'),
                                tooltip: _isMuted ? 'Unmute' : 'Mute',
                                icon: _isMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                onTap: _toggleMute,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: VideoTrimScrubber(
                                  key: const Key('updates_media_trim_scrubber'),
                                  videoPath: widget.localMediaPath,
                                  fullDurationSeconds:
                                      _videoFullDurationSeconds,
                                  trimStartSeconds: _trimStartSeconds,
                                  trimEndSeconds:
                                      _trimStartSeconds + _durationSeconds,
                                  minTrimSeconds: _minDurationSeconds,
                                  maxTrimSeconds: _maxDurationSeconds,
                                  onScrubStart: _handleTrimScrubStart,
                                  onScrubUpdate: _handleTrimScrubUpdate,
                                  onScrubEnd: _handleTrimScrubEnd,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // WhatsApp's own big center play/pause overlay -- only
                // shown while paused, tapping it resumes playback.
                if (_isVideo && !_isVideoPlaying)
                  Positioned.fill(
                    child: Center(
                      child: _VideoPlayPauseOverlay(
                        onTap: _toggleVideoPlayback,
                      ),
                    ),
                  ),
                // Crop mode's own floating controls, in the gap below the
                // media's bottom edge -- matches WhatsApp's own crop screen:
                // rotate at bottom-left, the ratio bubble at bottom-right,
                // Reset centered above them. Kept clear of the media itself
                // (rather than overlapping its bottom edge) so they never
                // sit on top of the free-form grid's own corner handles.
                if (_isCropMode) ...[
                  Positioned(
                    left: 14,
                    bottom: 74,
                    child: _GlassCircleButton(
                      key: const Key('updates_media_rotate_button'),
                      tooltip: 'Rotate',
                      icon: Icons.rotate_90_degrees_cw_rounded,
                      onTap: _rotateMediaClockwise,
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
                  if (_mediaTransform.scale != 1 ||
                      _mediaTransform.offsetDx != 0 ||
                      _mediaTransform.offsetDy != 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 130,
                      child: Center(
                        child: TextButton(
                          key: const Key('updates_media_crop_reset_button'),
                          onPressed: _resetMediaTransformOffset,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.32),
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
                    child: _DrawColorRail(
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const Key('updates_media_draw_eraser_button'),
                              tooltip: _isEraserMode ? 'Pen' : 'Eraser',
                              onPressed: () => setState(
                                () => _isEraserMode = !_isEraserMode,
                              ),
                              iconSize: 24,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(44, 44),
                                backgroundColor: _isEraserMode
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : null,
                              ),
                              icon: Icon(
                                _isEraserMode
                                    ? Icons.edit_rounded
                                    : Icons.auto_fix_off_rounded,
                                color: Colors.white,
                              ),
                            ),
                            for (var i = 0; i < _drawStrokeWidths.length; i++)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: _StrokeSizeButton(
                                  dotDiameter:
                                      (_isEraserMode ? 10.0 : 6.0) + i * 4.0,
                                  color: _isEraserMode
                                      ? Colors.white
                                      : _drawColor,
                                  selected: _drawStrokeWidth ==
                                      _drawStrokeWidths[i],
                                  onTap: () => setState(
                                    () => _drawStrokeWidth =
                                        _drawStrokeWidths[i],
                                  ),
                                ),
                              ),
                          ],
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
                                  child: _ComposerDeleteDropTarget(
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
                // never hidden behind whichever tool is active. A tool's
                // own tray (text style options, music banner style, blur
                // slider) floats directly above this row when relevant.
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_buildBottomCenterTray(isTextSelected)
                          case final tray?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: tray,
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _ComposerCaptionField(
                              controller: _captionController,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _ShareButton(onTap: _shareStatus),
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
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    this.videoController,
    this.videoInitialization,
    this.drawingStrokes = const <StatusDrawingStroke>[],
    this.frameSizeOverride,
  });

  final StatusStoryType type;
  final String localMediaPath;
  final StatusMediaTransform mediaTransform;
  final bool allowTransformGestures;
  final bool showFrameOutline;
  final ValueChanged<Size> onSourceSizeResolved;
  final VideoPlayerController? videoController;
  final Future<void>? videoInitialization;
  final GestureScaleStartCallback onScaleStart;
  final void Function(ScaleUpdateDetails details, Size canvasSize)
      onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final List<StatusDrawingStroke> drawingStrokes;
  final Size? frameSizeOverride;

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
          frameSizeOverride: frameSizeOverride,
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

/// The free-form crop grid: rule-of-thirds lines plus 4 draggable corner
/// handles over the current frame, matching WhatsApp's own crop screen.
/// Dragging a corner reshapes the frame to any custom ratio live -- the
/// actual resize math lives in the composer (it needs the canvas size and
/// current transform), this widget only reports raw per-frame drag deltas.
class _FreeformCropGrid extends StatelessWidget {
  const _FreeformCropGrid({
    required this.frameSize,
    required this.onCornerPanUpdate,
  });

  final Size frameSize;
  final void Function(_CropCorner corner, Offset delta) onCornerPanUpdate;

  static const double _handleHitSize = 44;
  static const double _handleVisualSize = 22;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: frameSize.width,
      height: frameSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: frameSize,
              painter: const _CropGridPainter(),
            ),
          ),
          _buildHandle(_CropCorner.topLeft),
          _buildHandle(_CropCorner.topRight),
          _buildHandle(_CropCorner.bottomLeft),
          _buildHandle(_CropCorner.bottomRight),
        ],
      ),
    );
  }

  Widget _buildHandle(_CropCorner corner) {
    final isLeft = corner == _CropCorner.topLeft ||
        corner == _CropCorner.bottomLeft;
    final isTop =
        corner == _CropCorner.topLeft || corner == _CropCorner.topRight;

    // Flush with the inside of the frame's corner rather than straddling
    // it -- when the frame fills the whole available canvas ("Fit to
    // screen"), a handle centered on the corner would overhang past the
    // physical screen edge and become unreachable.
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      width: _handleHitSize,
      height: _handleHitSize,
      child: GestureDetector(
        key: Key('updates_media_crop_corner_${corner.name}'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onCornerPanUpdate(corner, details.delta),
        child: Center(
          child: Container(
            width: _handleVisualSize,
            height: _handleVisualSize,
            decoration: BoxDecoration(
              border: Border(
                top: isTop
                    ? const BorderSide(color: Colors.white, width: 3)
                    : BorderSide.none,
                bottom: !isTop
                    ? const BorderSide(color: Colors.white, width: 3)
                    : BorderSide.none,
                left: isLeft
                    ? const BorderSide(color: Colors.white, width: 3)
                    : BorderSide.none,
                right: !isLeft
                    ? const BorderSide(color: Colors.white, width: 3)
                    : BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  const _CropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.56)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) => false;
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
    this.onDoubleTap,
    this.allowTransformGestures = true,
    super.key,
  });

  final StatusMediaOverlayItem item;
  final Size canvasSize;
  final bool isSelected;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
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
            child:
                allowTransformGestures || onTap != null || onDoubleTap != null
                    ? GestureDetector(
                        onTap: onTap,
                        onDoubleTap: onDoubleTap,
                        onScaleStart:
                            allowTransformGestures ? onScaleStart : null,
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

class _ComposerTopBar extends StatelessWidget {
  const _ComposerTopBar({
    required this.selectedOverlay,
    required this.isEditingText,
    required this.onClose,
    required this.onEditText,
    required this.onDoneEditing,
  });

  final StatusMediaOverlayItem? selectedOverlay;
  final bool isEditingText;
  final VoidCallback onClose;
  final VoidCallback onEditText;
  final VoidCallback onDoneEditing;

  @override
  Widget build(BuildContext context) {
    final hasTextSelection =
        selectedOverlay?.type == StatusMediaOverlayType.text;

    return Row(
      children: [
        _GlassCircleButton(
          key: const Key('updates_media_close_composer_button'),
          tooltip: 'Close',
          icon: Icons.close_rounded,
          onTap: onClose,
          showBorder: false,
        ),
        const Spacer(),
        if (hasTextSelection) ...[
          _GlassCircleButton(
            tooltip: isEditingText ? 'Done editing' : 'Edit text',
            icon: isEditingText ? Icons.check_rounded : Icons.edit_outlined,
            onTap: isEditingText ? onDoneEditing : onEditText,
          ),
        ],
      ],
    );
  }
}

class _ComposerDeleteDropTarget extends StatelessWidget {
  const _ComposerDeleteDropTarget({
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFE5484D)
                : Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.42)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isActive ? 0.28 : 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? Icons.delete_forever_rounded
                    : Icons.delete_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isActive ? 'Release to delete' : 'Drag here to delete',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _EditableTextOverlayCard extends StatelessWidget {
  const _EditableTextOverlayCard({
    required this.controller,
    required this.focusNode,
    required this.textStyleModel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final StatusTextStyle textStyleModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = resolveTextStatusFontLook(textStyleModel.fontId);
    final hasSolidBackground = textStyleModel.useSolidBackground ||
        textStyleModel.backgroundColor != null;
    final surfaceColor = (textStyleModel.backgroundColor ?? Colors.black)
        .withValues(alpha: hasSolidBackground ? 0.62 : 0.22);
    final textStyle = look.apply(
      (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: textStyleModel.textColor ?? Colors.white,
        fontSize: 24 * textStyleModel.sizeScale.clamp(0.72, 1.28),
        fontWeight: FontWeight.w800,
        height: 1.12,
        shadows: <Shadow>[
          Shadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 120,
        maxWidth: 320,
      ),
      child: Container(
        key: const Key('updates_media_inline_text_editor'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: TextField(
          key: const Key('updates_media_inline_text_field'),
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          textAlign: switch (textStyleModel.alignment) {
            StatusTextAlignment.left => TextAlign.left,
            StatusTextAlignment.center => TextAlign.center,
            StatusTextAlignment.right => TextAlign.right,
          },
          style: textStyle,
          cursorColor: textStyleModel.textColor ?? Colors.white,
          decoration: InputDecoration.collapsed(
            hintText: 'Type something',
            hintStyle: textStyle.copyWith(
              color: (textStyleModel.textColor ?? Colors.white)
                  .withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerTextEditingTray extends StatelessWidget {
  const _ComposerTextEditingTray({
    required this.textStyleModel,
    required this.onAddText,
    required this.onFontSelected,
    required this.onToneSelected,
    required this.onToggleBackground,
    required this.onCycleAlignment,
  });

  final StatusTextStyle textStyleModel;
  final VoidCallback onAddText;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<int?> onToneSelected;
  final VoidCallback onToggleBackground;
  final VoidCallback onCycleAlignment;

  void _cycleFont() {
    final currentIndex = kTextStatusFontLooks
        .indexWhere((look) => look.id == textStyleModel.fontId);
    final nextIndex = (currentIndex + 1) % kTextStatusFontLooks.length;
    onFontSelected(kTextStatusFontLooks[nextIndex].id);
  }

  void _cycleTone() {
    final currentIndex = kTextStatusTonePresets.indexWhere(
      (tone) => tone.colorValue == textStyleModel.textColorValue,
    );
    final nextIndex =
        (currentIndex == -1 ? 0 : currentIndex + 1) % kTextStatusTonePresets.length;
    onToneSelected(kTextStatusTonePresets[nextIndex].colorValue);
  }

  @override
  Widget build(BuildContext context) {
    // Mirrors the text-status composer's own top-bar icons exactly (single
    // tap cycles font/color) instead of the old chip-strip + S/M/L buttons
    // -- size is now a pinch gesture on the selected overlay itself, same
    // as every other overlay type already supports.
    return Container(
      key: const Key('updates_media_text_editing_tray'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarToolButton(
              key: const Key('updates_media_panel_fonts'),
              tooltip: 'Edit text',
              icon: Icons.edit_outlined,
              onTap: onAddText,
              isActive: true,
              expand: false,
            ),
            _ToolbarToolButton(
              key: const Key('updates_media_cycle_font_button'),
              tooltip: 'Change font',
              icon: Icons.font_download_outlined,
              onTap: _cycleFont,
              expand: false,
            ),
            _ToolbarToolButton(
              key: const Key('updates_media_cycle_tone_button'),
              tooltip: 'Change color',
              icon: Icons.palette_outlined,
              onTap: _cycleTone,
              expand: false,
            ),
            _ToolbarToolButton(
              key: const Key('updates_media_toggle_text_background_button'),
              tooltip: 'Toggle background',
              icon: textStyleModel.useSolidBackground
                  ? Icons.crop_square_rounded
                  : Icons.crop_landscape_rounded,
              onTap: onToggleBackground,
              isActive: textStyleModel.useSolidBackground,
              expand: false,
            ),
            _ToolbarToolButton(
              key: const Key('updates_media_cycle_alignment_button'),
              tooltip: 'Change alignment',
              icon: switch (textStyleModel.alignment) {
                StatusTextAlignment.left => Icons.format_align_left_rounded,
                StatusTextAlignment.center =>
                  Icons.format_align_center_rounded,
                StatusTextAlignment.right => Icons.format_align_right_rounded,
              },
              onTap: onCycleAlignment,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerMusicEditingTray extends StatelessWidget {
  const _ComposerMusicEditingTray({
    required this.onAddText,
    required this.selectedStyleId,
    required this.styleOptions,
    required this.onSelectStyle,
  });

  final VoidCallback onAddText;
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
          Row(
            children: [
              _ToolbarToolButton(
                key: const Key('updates_media_panel_fonts'),
                tooltip: 'Add text',
                icon: Icons.text_fields_rounded,
                onTap: onAddText,
                expand: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
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
class _DrawColorRail extends StatefulWidget {
  const _DrawColorRail({
    required this.selectedColor,
    required this.isEraserMode,
    required this.onSelectColor,
  });

  final Color selectedColor;
  final bool isEraserMode;
  final ValueChanged<Color> onSelectColor;

  @override
  State<_DrawColorRail> createState() => _DrawColorRailState();
}

class _DrawColorRailState extends State<_DrawColorRail> {
  double _barPosition = 0;

  void _updateFromLocalY(double localY, double height) {
    if (height <= 0) {
      return;
    }
    final position = (localY / height).clamp(0.0, 1.0);
    setState(() => _barPosition = position);
    widget.onSelectColor(_colorForDrawBarPosition(position));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('updates_media_draw_editing_tray'),
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return GestureDetector(
            key: const Key('updates_media_draw_color_bar'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            onVerticalDragStart: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            onVerticalDragUpdate: (details) =>
                _updateFromLocalY(details.localPosition.dy, height),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _kDrawColorBarStops,
                    ),
                  ),
                ),
                Positioned(
                  top: (_barPosition * height - 9)
                      .clamp(0.0, math.max(height - 18, 0.0)),
                  left: -5,
                  right: -5,
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('updates_media_draw_color_thumb'),
                      height: 18,
                      decoration: BoxDecoration(
                        color: widget.isEraserMode
                            ? Colors.transparent
                            : widget.selectedColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const List<Color> _kDrawColorBarStops = [
  Colors.white,
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF0A84FF),
  Color(0xFFBF5AF2),
  Colors.black,
];

Color _colorForDrawBarPosition(double t) {
  final stops = _kDrawColorBarStops;
  final segmentCount = stops.length - 1;
  final scaled = t.clamp(0.0, 1.0) * segmentCount;
  final index = scaled.floor().clamp(0, segmentCount - 1);
  final localT = scaled - index;
  return Color.lerp(stops[index], stops[index + 1], localT)!;
}

/// A stroke-width option shown as an actual dot at that size, in the pen's
/// current color -- shows you what the stroke will really look like,
/// instead of an abstract "S/M/L" label.
class _StrokeSizeButton extends StatelessWidget {
  const _StrokeSizeButton({
    required this.dotDiameter,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final double dotDiameter;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.white.withValues(alpha: 0.18) : null,
        ),
        child: Center(
          child: Container(
            width: dotDiameter,
            height: dotDiameter,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: color == Colors.white
                  ? Border.all(color: Colors.black26)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
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
              icon: hasMusic
                  ? Icons.graphic_eq_rounded
                  : Icons.music_note_rounded,
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
      ),
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

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.showBorder = true,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    // Fixed dark-glass look regardless of app theme -- this floats over the
    // photo/video canvas, not the system surface, so it stays legible there
    // no matter whether the rest of the app is in light or dark mode.
    return LiquidGlassIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      size: 42,
      iconSize: 20,
      iconColor: Colors.white,
      color: Colors.black.withValues(alpha: 0.28),
      borderColor:
          showBorder ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
    );
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
class _ComposerCaptionField extends StatelessWidget {
  const _ComposerCaptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        key: const Key('updates_media_caption_field'),
        controller: controller,
        maxLines: 3,
        minLines: 1,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Add a caption...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Same dark-glass chrome as every other floating control on this
    // screen (close, edit, toolbar icons) -- an emerald tint keeps it
    // reading as the primary action without breaking from that theme with
    // a solid, unrelated fill.
    return LiquidGlassIconButton(
      actionKey: const Key('updates_share_media_status_button'),
      icon: Icons.send_rounded,
      tooltip: 'Share status',
      onTap: onTap,
      size: 54,
      iconSize: 24,
      iconColor: Colors.white,
      color: AppPalette.emerald.withValues(alpha: 0.86),
      borderColor: Colors.white.withValues(alpha: 0.22),
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
    var flatEmojiIndex = 0;

    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stickers & emoji',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
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
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                  for (final category in kStatusEmojiCategories) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        category.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: category.emoji.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (context, i) {
                        final emoji = category.emoji[i];
                        final index = flatEmojiIndex++;
                        return InkWell(
                          key: Key('updates_media_emoji_option_$index'),
                          onTap: () => Navigator.of(context).pop(emoji),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.52),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: usesTwemoji(theme.platform)
                                  ? Semantics(
                                      label: emoji,
                                      child: ExcludeSemantics(
                                        child: Twemoji(
                                          emoji: emoji,
                                          width: 26,
                                          height: 26,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      emoji,
                                      style: emojiPreviewTextStyle(
                                        context,
                                        fontSize: 26,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
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
    return FractionallySizedBox(
      heightFactor: 0.68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add music',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
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
                            vertical: 10,
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
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
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
                              IconButton(
                                key: Key(
                                    'updates_media_music_play_button_$index'),
                                onPressed: () => onPlayPreview(track),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(40, 40),
                                  padding: EdgeInsets.zero,
                                  backgroundColor: isPreviewing
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: 0.14)
                                      : theme
                                          .colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.52),
                                ),
                                icon: Icon(
                                  isPreviewing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: isPreviewing
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
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

