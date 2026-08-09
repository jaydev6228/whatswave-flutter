import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/models/status_story.dart';
import '../../shared/widgets/liquid_glass.dart';
import 'widgets/status_media_decoration_overlay.dart';
import 'widgets/status_story_media_surface.dart';
import 'widgets/text_status_canvas.dart';

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
  });

  final String caption;
  final StatusTextStyle textStyle;
  final StatusMediaTransform mediaTransform;
  final List<StatusMediaOverlayItem> overlayItems;
  final String? emoji;
  final List<String> stickers;
  final StatusMusicTrack? musicTrack;
  final int durationMillis;
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

enum _FrameTraySelection {
  original,
  fourThree,
  sixteenNine,
  square,
  custom,
}

const EdgeInsets _kComposerOverlayReservedPadding = EdgeInsets.fromLTRB(
  18,
  84,
  18,
  28,
);

const List<String> _emojiFontFallback = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];

String? _preferredEmojiFontFamily(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
    TargetPlatform.android || TargetPlatform.linux => 'Noto Color Emoji',
    TargetPlatform.windows => 'Segoe UI Emoji',
    TargetPlatform.fuchsia => null,
  };
}

TextStyle _emojiPreviewTextStyle(
  BuildContext context, {
  required double fontSize,
}) {
  return TextStyle(
    inherit: false,
    fontSize: fontSize,
    fontFamily: _preferredEmojiFontFamily(Theme.of(context).platform),
    fontFamilyFallback: _emojiFontFallback,
  );
}

bool _usesTwemoji(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

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
    super.key,
  });

  final StatusStoryType type;
  final String localMediaPath;
  final Size? initialSourceSizeHint;

  @override
  State<MediaStatusComposerScreen> createState() =>
      _MediaStatusComposerScreenState();
}

class _MediaStatusComposerScreenState extends State<MediaStatusComposerScreen> {
  static const double _minOverlayPosition = 0.04;
  static const double _maxOverlayPosition = 0.96;

  static const List<String> _emojiPresets = <String>[
    '🔥',
    '✨',
    '😍',
    '🎉',
    '🤍',
    '😎',
    '🌙',
    '☕️',
    '📍',
    '🎧',
    '🌈',
    '💫',
  ];

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

  static const List<StatusMusicTrack> _musicPresets = <StatusMusicTrack>[
    StatusMusicTrack(
      id: 'city-pulse',
      title: 'City Pulse',
      artist: 'Whatswave House',
      colorValue: 0xFF25D366,
      secondaryColorValue: 0xFFD9FBE8,
      previewAssetPath: 'assets/audio/status_music/city_pulse.wav',
      bannerStyleId: 'cover',
    ),
    StatusMusicTrack(
      id: 'midnight-cab',
      title: 'Midnight Cab',
      artist: 'Neon Echo',
      colorValue: 0xFF58A6FF,
      secondaryColorValue: 0xFFDCEBFF,
      previewAssetPath: 'assets/audio/status_music/midnight_cab.wav',
      bannerStyleId: 'pulse',
    ),
    StatusMusicTrack(
      id: 'golden-hour',
      title: 'Golden Hour',
      artist: 'Soft Frames',
      colorValue: 0xFFFFC857,
      secondaryColorValue: 0xFFFFF1C5,
      previewAssetPath: 'assets/audio/status_music/golden_hour.wav',
      bannerStyleId: 'cover',
    ),
    StatusMusicTrack(
      id: 'afterglow',
      title: 'Afterglow',
      artist: 'Velvet Metro',
      colorValue: 0xFF8C6BFF,
      secondaryColorValue: 0xFFE8DFFF,
      previewAssetPath: 'assets/audio/status_music/afterglow.wav',
      bannerStyleId: 'mix',
    ),
    StatusMusicTrack(
      id: 'quiet-rain',
      title: 'Quiet Rain',
      artist: 'Cloudline',
      colorValue: 0xFF667781,
      secondaryColorValue: 0xFFE6EAEE,
      previewAssetPath: 'assets/audio/status_music/quiet_rain.wav',
      bannerStyleId: 'minimal',
    ),
    StatusMusicTrack(
      id: 'soft-static',
      title: 'Soft Static',
      artist: 'North Arcade',
      colorValue: 0xFFFF7AB6,
      secondaryColorValue: 0xFFFFDAEB,
      previewAssetPath: 'assets/audio/status_music/soft_static.wav',
      bannerStyleId: 'mix',
    ),
    StatusMusicTrack(
      id: 'dawn-run',
      title: 'Dawn Run',
      artist: 'Early Shift',
      colorValue: 0xFFFD8D4F,
      secondaryColorValue: 0xFFFFE4D0,
      previewAssetPath: 'assets/audio/status_music/dawn_run.wav',
      bannerStyleId: 'pulse',
    ),
    StatusMusicTrack(
      id: 'sea-breeze',
      title: 'Sea Breeze',
      artist: 'Blue Relay',
      colorValue: 0xFF3FC2D6,
      secondaryColorValue: 0xFFD9F7FB,
      previewAssetPath: 'assets/audio/status_music/sea_breeze.wav',
      bannerStyleId: 'cover',
    ),
    StatusMusicTrack(
      id: 'retro-lines',
      title: 'Retro Lines',
      artist: 'Tape Bloom',
      colorValue: 0xFFF97316,
      secondaryColorValue: 0xFFFFE5D4,
      previewAssetPath: 'assets/audio/status_music/retro_lines.wav',
      bannerStyleId: 'minimal',
    ),
    StatusMusicTrack(
      id: 'moonlit-steps',
      title: 'Moonlit Steps',
      artist: 'Low Tide',
      colorValue: 0xFF7C8BFF,
      secondaryColorValue: 0xFFE0E4FF,
      previewAssetPath: 'assets/audio/status_music/moonlit_steps.wav',
      bannerStyleId: 'mix',
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
  StatusMediaTransform _mediaTransform = const StatusMediaTransform();
  final List<StatusMediaOverlayItem> _overlayItems = <StatusMediaOverlayItem>[];
  late final TextEditingController _inlineTextController;
  late final FocusNode _inlineTextFocusNode;
  final GlobalKey _deleteTargetKey = GlobalKey();
  String? _selectedOverlayId;
  String? _editingTextOverlayId;
  StatusMusicTrack? _musicTrack;
  String? _previewingMusicTrackId;
  bool _showOverlayGuide = false;
  bool _showFrameEditingTray = false;
  bool _isDeleteTargetActive = false;
  bool _isDraggingOverlay = false;
  Timer? _overlayGuideTimer;
  double _customFrameAspectRatio = 1.15;
  double? _originalMediaAspectRatio;
  bool _didSeedInitialMediaFrame = false;
  StatusMediaTransform? _frameEditingStartTransform;
  double? _frameEditingStartCustomAspectRatio;

  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;
  VideoPlayerController? _musicPreviewController;
  bool _didAdjustDurationManually = false;

  StatusMediaOverlayItem? _gestureAnchorOverlay;
  Offset? _gestureStartFocalPoint;
  StatusMediaTransform? _mediaGestureAnchorTransform;
  Offset? _mediaGestureStartFocalPoint;

  int _nextOverlaySeed = 0;

  bool get _isVideo => widget.type == StatusStoryType.video;
  bool get _isEditingTextOverlay => _editingTextOverlayId != null;
  bool get _allowMediaTransformGestures =>
      !_showFrameEditingTray &&
      !_isEditingTextOverlay &&
      _selectedOverlayId == null &&
      _gestureAnchorOverlay == null &&
      !_isDraggingOverlay;

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

  String get _summaryCaption => _primaryTextOverlay?.label.trim() ?? '';

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

  _FrameTraySelection get _activeFrameSelection {
    final aspectRatio = _mediaTransform.frameAspectRatio;
    if (aspectRatio == null ||
        _matchesAspectRatio(aspectRatio, _originalMediaAspectRatio)) {
      return _FrameTraySelection.original;
    }
    if ((aspectRatio - (4 / 3)).abs() < 0.02) {
      return _FrameTraySelection.fourThree;
    }
    if ((aspectRatio - (16 / 9)).abs() < 0.02) {
      return _FrameTraySelection.sixteenNine;
    }
    if ((aspectRatio - 1).abs() < 0.02) {
      return _FrameTraySelection.square;
    }
    return _FrameTraySelection.custom;
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
    final shouldSeedFrame = !_didSeedInitialMediaFrame &&
        _mediaTransform.frameAspectRatio == null &&
        !_showFrameEditingTray &&
        _frameEditingStartTransform == null;
    final shouldKeepFrameSyncedToOriginal = !shouldSeedFrame &&
        previousOriginalAspectRatio != null &&
        !_showFrameEditingTray &&
        _frameEditingStartTransform == null &&
        _matchesAspectRatio(
          _mediaTransform.frameAspectRatio,
          previousOriginalAspectRatio,
        ) &&
        !_matchesAspectRatio(previousOriginalAspectRatio, aspectRatio);

    final clampedCustomAspect = aspectRatio.clamp(0.75, 1.9).toDouble();
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
        _customFrameAspectRatio = clampedCustomAspect;
        _didSeedInitialMediaFrame = true;
      }
    }

    if (allowSetState) {
      setState(syncFrame);
      return;
    }

    syncFrame();
  }

  void _resetFrameEditingState({required bool revertChanges}) {
    if (revertChanges && _frameEditingStartTransform != null) {
      _mediaTransform = _frameEditingStartTransform!;
      if (_frameEditingStartCustomAspectRatio != null) {
        _customFrameAspectRatio = _frameEditingStartCustomAspectRatio!;
      }
    }
    _showFrameEditingTray = false;
    _frameEditingStartTransform = null;
    _frameEditingStartCustomAspectRatio = null;
  }

  void _resetMediaGestureState() {
    _mediaGestureAnchorTransform = null;
    _mediaGestureStartFocalPoint = null;
  }

  void _startFrameEditing() {
    _commitInlineTextEditing(clearSelection: false);
    setState(() {
      _resetMediaGestureState();
      _frameEditingStartTransform = _mediaTransform;
      _frameEditingStartCustomAspectRatio = _customFrameAspectRatio;
      _showFrameEditingTray = true;
      _selectedOverlayId = null;
      _showOverlayGuide = false;
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
  }

  void _finishFrameEditing({bool revertChanges = false}) {
    if (!_showFrameEditingTray &&
        _frameEditingStartTransform == null &&
        _frameEditingStartCustomAspectRatio == null) {
      return;
    }
    setState(() {
      _resetMediaGestureState();
      _resetFrameEditingState(revertChanges: revertChanges);
      _selectedOverlayId = null;
      _showOverlayGuide = false;
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
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

    final controller = VideoPlayerController.asset(assetPath);
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
      await controller.setLooping(true);
      // The preview should sound the same as the posted story does: the
      // video's own audio plays by default, muted only when a music track
      // is layered on top of it (matching status_story_viewer_screen.dart's
      // identical video-vs-music volume logic). Previously always muted
      // unconditionally, so a picked video had no sound until after
      // posting.
      await controller.setVolume(_musicTrack == null ? 1 : 0);
      await controller.play();
      _adoptOriginalMediaFrameIfNeeded(controller.value.size);

      if (!_didAdjustDurationManually &&
          controller.value.duration > Duration.zero) {
        _durationSeconds = controller.value.duration.inSeconds
            .clamp(_minDurationSeconds.round(), _maxDurationSeconds.round())
            .toDouble();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  void _shareStatus() {
    _commitInlineTextEditing(clearSelection: false);
    Navigator.of(context).pop(
      MediaStatusComposerDraft(
        caption: _summaryCaption,
        textStyle: _summaryTextStyle,
        mediaTransform: _mediaTransform,
        overlayItems: _normalizedShareableOverlayItems(),
        emoji: _leadEmoji,
        stickers: _stickerLabels,
        musicTrack: _musicTrack,
        durationMillis: _durationMillis,
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
  }) {
    final effectiveFrameSize =
        frameSize ?? _overlayFrameSizeForCurrentContext();
    if (effectiveFrameSize.width <= 0 || effectiveFrameSize.height <= 0) {
      return item;
    }

    final normalizedScale = item.scale.clamp(0.6, 3.0).toDouble();
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
      _resetFrameEditingState(revertChanges: false);
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
    _clearSelection();
  }

  void _clearSelection() {
    _overlayGuideTimer?.cancel();
    if (_selectedOverlayId == null &&
        _editingTextOverlayId == null &&
        !_showOverlayGuide &&
        !_showFrameEditingTray) {
      return;
    }
    setState(() {
      _resetMediaGestureState();
      _selectedOverlayId = null;
      _editingTextOverlayId = null;
      _showOverlayGuide = false;
      _resetFrameEditingState(revertChanges: false);
      _isDeleteTargetActive = false;
      _isDraggingOverlay = false;
    });
    _inlineTextFocusNode.unfocus();
  }

  void _upsertOverlay(StatusMediaOverlayItem item, {bool select = true}) {
    final normalizedItem = _normalizedOverlayItemForCurrentFrame(item);
    setState(() {
      _overlayItems.removeWhere((entry) => entry.id == normalizedItem.id);
      _overlayItems.add(normalizedItem);
      if (select) {
        _selectedOverlayId = normalizedItem.id;
        _resetFrameEditingState(revertChanges: false);
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
        // Music removed -- give the video its own audio back.
        unawaited(_videoController?.setVolume(1));
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

  Future<void> _openCustomTonePicker() async {
    final selectedOverlay = _selectedOverlay;
    if (selectedOverlay == null ||
        selectedOverlay.type != StatusMediaOverlayType.text) {
      return;
    }

    final selection = await showModalBottomSheet<Color>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return _TextTonePickerSheet(
          initialColor: selectedOverlay.textStyle?.textColor ?? Colors.white,
        );
      },
    );
    if (!mounted || selection == null) {
      return;
    }

    _updateSelectedTextStyle(
      (style) => style.copyWith(textColorValue: selection.toARGB32()),
    );
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

  Future<void> _openEmojiPicker() async {
    final theme = Theme.of(context);
    final emoji = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return _EmojiPickerSheet(
          emojiPresets: _emojiPresets,
        );
      },
    );
    if (!mounted || emoji == null || emoji.isEmpty) {
      return;
    }

    final position = _suggestedNormalizedPosition(baseDx: 0.72, baseDy: 0.28);
    _upsertOverlay(
      StatusMediaOverlayItem(
        id: _nextOverlayId('emoji'),
        type: StatusMediaOverlayType.emoji,
        label: emoji,
        positionDx: position.dx,
        positionDy: position.dy,
        scale: 1.18,
        rotation: 0,
      ),
    );
  }

  Future<void> _openStickerPicker() async {
    final theme = Theme.of(context);
    final sticker = await showModalBottomSheet<_StickerPreset>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return _StickerPickerSheet(stickerPresets: _stickerPresets);
      },
    );
    if (!mounted || sticker == null || sticker.label.trim().isEmpty) {
      return;
    }

    final position = _suggestedNormalizedPosition(baseDx: 0.48, baseDy: 0.34);
    _upsertOverlay(
      StatusMediaOverlayItem(
        id: _nextOverlayId('sticker'),
        type: StatusMediaOverlayType.sticker,
        label: sticker.label.trim(),
        positionDx: position.dx,
        positionDy: position.dy,
        scale: 1,
        rotation: 0,
        accentColorValue: sticker.accentColorValue,
        secondaryColorValue: sticker.secondaryColorValue,
        variantId: sticker.id,
      ),
    );
  }

  Future<void> _openMusicPicker() async {
    final theme = Theme.of(context);
    final selectedTrack = await showModalBottomSheet<StatusMusicTrack?>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return _MusicPickerSheet(
          tracks: _musicPresets,
          selectedTrackId: _musicTrack?.id,
          previewingTrackId: _previewingMusicTrackId,
          onPlayPreview: (track) =>
              _playMusicPreview(track, toggleWhenSameTrack: true),
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
      _resetFrameEditingState(revertChanges: false);
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

  Future<void> _openTimingSheet() async {
    final selection = await showModalBottomSheet<double>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return _TimingSheet(
          initialValue:
              _durationSeconds.clamp(_minDurationSeconds, _maxDurationSeconds),
          minDurationSeconds: _minDurationSeconds,
          maxDurationSeconds: _maxDurationSeconds,
        );
      },
    );
    if (!mounted || selection == null) {
      return;
    }
    _updateDuration(selection);
  }

  void _updateDuration(double value) {
    setState(() {
      _didAdjustDurationManually = true;
      _durationSeconds = value.clamp(_minDurationSeconds, _maxDurationSeconds);
    });
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
    final clampedPosition = _clampOverlayPosition(
      item: anchorOverlay,
      canvasSize: canvasSize,
      positionDx: nextDx,
      positionDy: nextDy,
      scale: nextScale,
    );

    _upsertOverlay(
      anchorOverlay.copyWith(
        positionDx: clampedPosition.dx,
        positionDy: clampedPosition.dy,
        scale: nextScale,
        rotation: anchorOverlay.rotation + details.rotation,
      ),
    );
    _updateDeleteTargetHover(
      globalFocalPoint: details.focalPoint,
      isDraggingOverlay: true,
    );
  }

  void _onOverlayScaleEnd(ScaleEndDetails details) {
    final overlayToDelete =
        _isDeleteTargetActive ? _gestureAnchorOverlay : null;
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

  void _toggleFrameEditingTray() {
    if (_showFrameEditingTray) {
      _finishFrameEditing();
      return;
    }
    _startFrameEditing();
  }

  void _applyFrameSelection(_FrameTraySelection selection) {
    setState(() {
      _selectedOverlayId = null;
      _showOverlayGuide = false;
      switch (selection) {
        case _FrameTraySelection.original:
          final originalAspectRatio = _originalMediaAspectRatio;
          _mediaTransform = originalAspectRatio == null
              ? _mediaTransform.copyWith(clearFrameAspectRatio: true)
              : _mediaTransform.copyWith(frameAspectRatio: originalAspectRatio);
          break;
        case _FrameTraySelection.fourThree:
          _mediaTransform = _mediaTransform.copyWith(frameAspectRatio: 4 / 3);
          break;
        case _FrameTraySelection.sixteenNine:
          _mediaTransform = _mediaTransform.copyWith(frameAspectRatio: 16 / 9);
          break;
        case _FrameTraySelection.square:
          _mediaTransform = _mediaTransform.copyWith(frameAspectRatio: 1);
          break;
        case _FrameTraySelection.custom:
          _mediaTransform = _mediaTransform.copyWith(
            frameAspectRatio: _customFrameAspectRatio,
          );
          break;
      }
    });
  }

  void _updateCustomFrameAspect(double value) {
    setState(() {
      _customFrameAspectRatio = value;
      _mediaTransform = _mediaTransform.copyWith(frameAspectRatio: value);
    });
  }

  void _rotateMediaClockwise() {
    setState(() {
      _mediaTransform = _mediaTransform.copyWith(
        rotationQuarterTurns: _mediaTransform.rotationQuarterTurns + 1,
      );
    });
  }

  Size _mediaFrameSizeFor(Size canvasSize) {
    return statusStoryFrameSizeFor(
      canvasSize,
      _mediaTransform.frameAspectRatio,
    );
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
    final showPlacementGuide = (_showOverlayGuide || _isEditingTextOverlay) &&
        _overlayItems.isNotEmpty;

    return Scaffold(
      key: const Key('updates_media_composer_screen'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ComposerMediaLayer(
            type: widget.type,
            localMediaPath: widget.localMediaPath,
            mediaTransform: _mediaTransform,
            videoController: _videoController,
            videoInitialization: _videoInitialization,
            allowTransformGestures: _allowMediaTransformGestures,
            showFrameOutline: _showFrameEditingTray || showPlacementGuide,
            onSourceSizeResolved: _adoptOriginalMediaFrameIfNeeded,
            onScaleStart: _onMediaScaleStart,
            onScaleUpdate: _onMediaScaleUpdate,
            onScaleEnd: _onMediaScaleEnd,
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
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 140),
                            child: showPlacementGuide
                                ? LayoutBuilder(
                                    key: const Key(
                                      'updates_media_overlay_guide_frame',
                                    ),
                                    builder: (context, constraints) {
                                      final frameSize = statusStoryFrameSizeFor(
                                        Size(
                                          constraints.maxWidth,
                                          constraints.maxHeight,
                                        ),
                                        _mediaTransform.frameAspectRatio,
                                      );
                                      final safeRect =
                                          _composerOverlaySafeRectForFrame(
                                        frameSize,
                                      );
                                      return Center(
                                        child: SizedBox(
                                          width: frameSize.width,
                                          height: frameSize.height,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: safeRect.left,
                                                top: safeRect.top,
                                                width: safeRect.width,
                                                height: safeRect.height,
                                                child:
                                                    const _ComposerPlacementGuide(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: _ComposerTopBar(
                    selectedOverlay: _selectedOverlay,
                    isEditingText: _isEditingTextOverlay,
                    isFrameEditing: _showFrameEditingTray,
                    onClose: () => Navigator.of(context).maybePop(),
                    onCancelFrameEditing: () =>
                        _finishFrameEditing(revertChanges: true),
                    onEditText: _editSelectedTextOverlay,
                    onDoneEditing: () =>
                        _commitInlineTextEditing(clearSelection: false),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 92,
                  child: _selectedOverlay == null ||
                          _showFrameEditingTray ||
                          _isEditingTextOverlay
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
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: isTextSelected
                            ? _ComposerTextEditingTray(
                                textStyleModel: _activeTextStyle,
                                onAddText: _selectedOverlay?.type ==
                                        StatusMediaOverlayType.text
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
                                onOpenTonePicker: _openCustomTonePicker,
                                onToggleBackground: () {
                                  _updateSelectedTextStyle((style) {
                                    final nextSelected =
                                        !style.useSolidBackground;
                                    return style.copyWith(
                                      useSolidBackground: nextSelected,
                                      backgroundColorValue: nextSelected
                                          ? (style.backgroundColorValue ??
                                              0xCC101418)
                                          : null,
                                      clearBackgroundColor: !nextSelected,
                                    );
                                  });
                                },
                                onCycleAlignment: () {
                                  _updateSelectedTextStyle((style) {
                                    final nextAlignment =
                                        switch (style.alignment) {
                                      StatusTextAlignment.left =>
                                        StatusTextAlignment.center,
                                      StatusTextAlignment.center =>
                                        StatusTextAlignment.right,
                                      StatusTextAlignment.right =>
                                        StatusTextAlignment.left,
                                    };
                                    return style.copyWith(
                                      alignment: nextAlignment,
                                    );
                                  });
                                },
                                onSelectSize: (sizeScale) {
                                  _updateSelectedTextStyle(
                                    (style) =>
                                        style.copyWith(sizeScale: sizeScale),
                                  );
                                },
                              )
                            : _showFrameEditingTray
                                ? _ComposerFrameEditingTray(
                                    selectedFrame: _activeFrameSelection,
                                    customAspectRatio: _customFrameAspectRatio,
                                    onSelectFrame: _applyFrameSelection,
                                    onCustomAspectChanged:
                                        _updateCustomFrameAspect,
                                    onRotate: _rotateMediaClockwise,
                                  )
                                : _selectedOverlay?.type ==
                                        StatusMediaOverlayType.music
                                    ? _ComposerMusicEditingTray(
                                        onAddText: _addTextOverlay,
                                        selectedStyleId: _selectedMusicStyleId,
                                        styleOptions: _musicBannerStyles,
                                        onSelectStyle:
                                            _updateSelectedMusicStyle,
                                      )
                                    : _ComposerToolbar(
                                        durationLabel:
                                            '${_durationSeconds.round()}s',
                                        hasMusic: _musicTrack != null,
                                        isTextSelected: false,
                                        onAddText: _addTextOverlay,
                                        onAddEmoji: _openEmojiPicker,
                                        onAddSticker: _openStickerPicker,
                                        onAddMusic: _openMusicPicker,
                                        onEditFrame: _toggleFrameEditingTray,
                                        onEditTiming: _openTimingSheet,
                                      ),
                      ),
                      const SizedBox(width: 12),
                      _showFrameEditingTray
                          ? _DoneButton(onTap: () => _finishFrameEditing())
                          : _ShareButton(onTap: _shareStatus),
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
    required this.isFrameEditing,
    required this.onClose,
    required this.onCancelFrameEditing,
    required this.onEditText,
    required this.onDoneEditing,
  });

  final StatusMediaOverlayItem? selectedOverlay;
  final bool isEditingText;
  final bool isFrameEditing;
  final VoidCallback onClose;
  final VoidCallback onCancelFrameEditing;
  final VoidCallback onEditText;
  final VoidCallback onDoneEditing;

  @override
  Widget build(BuildContext context) {
    final hasTextSelection =
        selectedOverlay?.type == StatusMediaOverlayType.text;

    return Row(
      children: [
        _GlassCircleButton(
          key: Key(
            isFrameEditing
                ? 'updates_media_cancel_frame_editing_button'
                : 'updates_media_close_composer_button',
          ),
          tooltip: isFrameEditing ? 'Cancel frame editing' : 'Close',
          icon: isFrameEditing ? Icons.arrow_back_rounded : Icons.close_rounded,
          onTap: isFrameEditing ? onCancelFrameEditing : onClose,
        ),
        const Spacer(),
        if (!isFrameEditing && hasTextSelection) ...[
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

class _ComposerPlacementGuide extends StatelessWidget {
  const _ComposerPlacementGuide();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('updates_media_overlay_guide'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.56),
          width: 1.1,
        ),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.04),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: const [
          _GuideCorner(alignment: Alignment.topLeft),
          _GuideCorner(alignment: Alignment.topRight),
          _GuideCorner(alignment: Alignment.bottomLeft),
          _GuideCorner(alignment: Alignment.bottomRight),
        ],
      ),
    );
  }
}

class _GuideCorner extends StatelessWidget {
  const _GuideCorner({
    required this.alignment,
  });

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border(
            top: isTop
                ? BorderSide(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 2.2,
                  )
                : BorderSide.none,
            bottom: !isTop
                ? BorderSide(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 2.2,
                  )
                : BorderSide.none,
            left: isLeft
                ? BorderSide(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 2.2,
                  )
                : BorderSide.none,
            right: !isLeft
                ? BorderSide(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 2.2,
                  )
                : BorderSide.none,
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
    required this.onOpenTonePicker,
    required this.onToggleBackground,
    required this.onCycleAlignment,
    required this.onSelectSize,
  });

  final StatusTextStyle textStyleModel;
  final VoidCallback onAddText;
  final ValueChanged<String> onFontSelected;
  final ValueChanged<int?> onToneSelected;
  final VoidCallback onOpenTonePicker;
  final VoidCallback onToggleBackground;
  final VoidCallback onCycleAlignment;
  final ValueChanged<double> onSelectSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('updates_media_text_editing_tray'),
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
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolbarToolButton(
                  key: const Key('updates_media_panel_fonts'),
                  tooltip: 'Edit text',
                  icon: Icons.text_fields_rounded,
                  onTap: onAddText,
                  isActive: true,
                  expand: false,
                ),
                _ToolbarToolButton(
                  tooltip: 'Pick custom color',
                  icon: Icons.palette_outlined,
                  onTap: onOpenTonePicker,
                  expand: false,
                ),
                _ToolbarToolButton(
                  tooltip: 'Toggle background',
                  icon: textStyleModel.useSolidBackground
                      ? Icons.crop_square_rounded
                      : Icons.crop_landscape_rounded,
                  onTap: onToggleBackground,
                  isActive: textStyleModel.useSolidBackground,
                  expand: false,
                ),
                _ToolbarToolButton(
                  tooltip: 'Change alignment',
                  icon: switch (textStyleModel.alignment) {
                    StatusTextAlignment.left => Icons.format_align_left_rounded,
                    StatusTextAlignment.center =>
                      Icons.format_align_center_rounded,
                    StatusTextAlignment.right =>
                      Icons.format_align_right_rounded,
                  },
                  onTap: onCycleAlignment,
                  expand: false,
                ),
                for (final entry in <(double, String)>[
                  (0.86, 'S'),
                  (1.0, 'M'),
                  (1.16, 'L'),
                ])
                  _TraySizeButton(
                    label: entry.$2,
                    selected:
                        (textStyleModel.sizeScale - entry.$1).abs() < 0.02,
                    onTap: () => onSelectSize(entry.$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.separated(
              key: const Key('updates_media_inline_font_row'),
              scrollDirection: Axis.horizontal,
              itemCount: kTextStatusFontLooks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final font = kTextStatusFontLooks[index];
                return _FontLookChip(
                  key: Key('updates_media_font_${font.id}'),
                  look: font,
                  isSelected: textStyleModel.fontId == font.id,
                  onTap: () => onFontSelected(font.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              key: const Key('updates_media_inline_tone_row'),
              scrollDirection: Axis.horizontal,
              itemCount: kTextStatusTonePresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final tone = kTextStatusTonePresets[index];
                return _ToneSwatchChip(
                  tone: tone,
                  isSelected: textStyleModel.textColorValue == tone.colorValue,
                  onTap: () => onToneSelected(tone.colorValue),
                );
              },
            ),
          ),
        ],
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

class _ComposerFrameEditingTray extends StatelessWidget {
  const _ComposerFrameEditingTray({
    required this.selectedFrame,
    required this.customAspectRatio,
    required this.onSelectFrame,
    required this.onCustomAspectChanged,
    required this.onRotate,
  });

  final _FrameTraySelection selectedFrame;
  final double customAspectRatio;
  final ValueChanged<_FrameTraySelection> onSelectFrame;
  final ValueChanged<double> onCustomAspectChanged;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('updates_media_frame_editing_tray'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FrameOptionChip(
                  key: const Key('updates_media_frame_option_original'),
                  label: 'Original',
                  selected: selectedFrame == _FrameTraySelection.original,
                  onTap: () => onSelectFrame(_FrameTraySelection.original),
                ),
                _FrameOptionChip(
                  key: const Key('updates_media_frame_option_four_three'),
                  label: '4:3',
                  selected: selectedFrame == _FrameTraySelection.fourThree,
                  onTap: () => onSelectFrame(_FrameTraySelection.fourThree),
                ),
                _FrameOptionChip(
                  key: const Key('updates_media_frame_option_sixteen_nine'),
                  label: '16:9',
                  selected: selectedFrame == _FrameTraySelection.sixteenNine,
                  onTap: () => onSelectFrame(_FrameTraySelection.sixteenNine),
                ),
                _FrameOptionChip(
                  key: const Key('updates_media_frame_option_square'),
                  label: '1:1',
                  selected: selectedFrame == _FrameTraySelection.square,
                  onTap: () => onSelectFrame(_FrameTraySelection.square),
                ),
                _FrameOptionChip(
                  key: const Key('updates_media_frame_option_custom'),
                  label: 'Custom',
                  selected: selectedFrame == _FrameTraySelection.custom,
                  onTap: () => onSelectFrame(_FrameTraySelection.custom),
                ),
                const SizedBox(width: 4),
                _MiniOptionChip(
                  key: const Key('updates_media_rotate_button'),
                  selected: false,
                  onTap: onRotate,
                  icon: Icons.rotate_90_degrees_cw_rounded,
                ),
              ],
            ),
          ),
          if (selectedFrame == _FrameTraySelection.custom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Wide',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      key: const Key('updates_media_frame_custom_slider'),
                      value: customAspectRatio.clamp(0.75, 1.9),
                      min: 0.75,
                      max: 1.9,
                      divisions: 23,
                      onChanged: onCustomAspectChanged,
                    ),
                  ),
                ),
                Text(
                  'Tall',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FrameOptionChip extends StatelessWidget {
  const _FrameOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _MiniOptionChip(
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class _TraySizeButton extends StatelessWidget {
  const _TraySizeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      child: _MiniOptionChip(
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.durationLabel,
    required this.hasMusic,
    required this.isTextSelected,
    required this.onAddText,
    required this.onAddEmoji,
    required this.onAddSticker,
    required this.onAddMusic,
    required this.onEditFrame,
    required this.onEditTiming,
  });

  final String durationLabel;
  final bool hasMusic;
  final bool isTextSelected;
  final VoidCallback onAddText;
  final VoidCallback onAddEmoji;
  final VoidCallback onAddSticker;
  final VoidCallback onAddMusic;
  final VoidCallback onEditFrame;
  final VoidCallback onEditTiming;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _ToolbarToolButton(
            key: const Key('updates_media_panel_fonts'),
            tooltip: isTextSelected ? 'Edit text' : 'Add text',
            icon: isTextSelected
                ? Icons.edit_outlined
                : Icons.text_fields_rounded,
            onTap: onAddText,
            isActive: isTextSelected,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_add_emoji_button'),
            tooltip: 'Add emoji',
            icon: Icons.emoji_emotions_outlined,
            onTap: onAddEmoji,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_add_sticker_button'),
            tooltip: 'Add sticker',
            icon: Icons.sell_outlined,
            onTap: onAddSticker,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_add_music_button'),
            tooltip: hasMusic ? 'Change music' : 'Add music',
            icon:
                hasMusic ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
            onTap: onAddMusic,
            isActive: hasMusic,
          ),
          _ToolbarToolButton(
            key: const Key('updates_media_frame_button'),
            tooltip: 'Adjust frame',
            icon: Icons.aspect_ratio_rounded,
            onTap: onEditFrame,
          ),
          _ToolbarTimeButton(
            key: const Key('updates_media_edit_timing_button'),
            tooltip: 'Change status duration',
            label: durationLabel,
            onTap: onEditTiming,
          ),
        ],
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

class _ToolbarTimeButton extends StatelessWidget {
  const _ToolbarTimeButton({
    required this.tooltip,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String tooltip;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

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
      borderColor: Colors.white.withValues(alpha: 0.18),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const Key('updates_share_media_status_button'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.emerald,
        foregroundColor: Colors.white,
        minimumSize: const Size(54, 54),
        maximumSize: const Size(54, 54),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        elevation: 0,
      ),
      child: const Icon(Icons.send_rounded, size: 24),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const Key('updates_done_frame_editing_button'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size(54, 54),
        maximumSize: const Size(54, 54),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        elevation: 0,
      ),
      child: const Icon(Icons.check_rounded, size: 24),
    );
  }
}

class _FontLookChip extends StatelessWidget {
  const _FontLookChip({
    required this.look,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final TextStatusFontLook look;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sampleStyle = look.apply(
      (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 50,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.82)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Center(
          child: Text(
            look.uppercase ? look.sample.toUpperCase() : look.sample,
            style: sampleStyle,
          ),
        ),
      ),
    );
  }
}

class _ToneSwatchChip extends StatelessWidget {
  const _ToneSwatchChip({
    required this.tone,
    required this.isSelected,
    required this.onTap,
  });

  final TextStatusTonePreset tone;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone.color;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.44),
            width: isSelected ? 2.2 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: color == null
            ? Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}

class _MiniOptionChip extends StatelessWidget {
  const _MiniOptionChip({
    super.key,
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

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({
    required this.emojiPresets,
  });

  final List<String> emojiPresets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add emoji',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < emojiPresets.length; index++)
                InkWell(
                  key: Key('updates_media_emoji_option_$index'),
                  onTap: () => Navigator.of(context).pop(emojiPresets[index]),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: _usesTwemoji(theme.platform)
                          ? Semantics(
                              label: emojiPresets[index],
                              child: ExcludeSemantics(
                                child: Twemoji(
                                  emoji: emojiPresets[index],
                                  width: 28,
                                  height: 28,
                                ),
                              ),
                            )
                          : Text(
                              emojiPresets[index],
                              style: _emojiPreviewTextStyle(
                                context,
                                fontSize: 28,
                              ),
                            ),
                      ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StickerPickerSheet extends StatelessWidget {
  const _StickerPickerSheet({
    required this.stickerPresets,
  });

  final List<_StickerPreset> stickerPresets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add sticker',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stickerPresets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
            ),
            itemBuilder: (context, index) {
              final preset = stickerPresets[index];
              final previewItem = StatusMediaOverlayItem(
                id: 'sticker-preview-${preset.id}',
                type: StatusMediaOverlayType.sticker,
                label: preset.label,
                accentColorValue: preset.accentColorValue,
                secondaryColorValue: preset.secondaryColorValue,
                variantId: preset.id,
              );
              return InkWell(
                key: Key('updates_media_sticker_option_$index'),
                onTap: () => Navigator.of(context).pop(preset),
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Center(
                    child: StatusOverlayContent(
                      item: previewItem,
                      compact: false,
                      accentColor: Color(preset.accentColorValue),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
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

class _TimingSheet extends StatefulWidget {
  const _TimingSheet({
    required this.initialValue,
    required this.minDurationSeconds,
    required this.maxDurationSeconds,
  });

  final double initialValue;
  final double minDurationSeconds;
  final double maxDurationSeconds;

  @override
  State<_TimingSheet> createState() => _TimingSheetState();
}

class _TimingSheetState extends State<_TimingSheet> {
  late double _durationSeconds;

  @override
  void initState() {
    super.initState();
    _durationSeconds = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Story duration',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            key: const Key('updates_media_status_timing_slider'),
            value: _durationSeconds.clamp(
              widget.minDurationSeconds,
              widget.maxDurationSeconds,
            ),
            min: widget.minDurationSeconds,
            max: widget.maxDurationSeconds,
            divisions:
                (widget.maxDurationSeconds - widget.minDurationSeconds).round(),
            label: '${_durationSeconds.round()}s',
            onChanged: (value) {
              setState(() {
                _durationSeconds = value;
              });
            },
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_durationSeconds.round()} seconds',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_durationSeconds),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextTonePickerSheet extends StatefulWidget {
  const _TextTonePickerSheet({
    required this.initialColor,
  });

  final Color initialColor;

  @override
  State<_TextTonePickerSheet> createState() => _TextTonePickerSheetState();
}

class _TextTonePickerSheetState extends State<_TextTonePickerSheet> {
  late HSVColor _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = HSVColor.fromColor(widget.initialColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _selectedColor.toColor();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick text color',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.82),
                    width: 1.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _hexLabel(color),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                'Aa',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.18,
            child: _ToneSaturationValueBoard(
              color: _selectedColor,
              onChanged: (color) {
                setState(() {
                  _selectedColor = color;
                });
              },
            ),
          ),
          const SizedBox(height: 18),
          _ToneHueSpectrumSlider(
            hue: _selectedColor.hue,
            onChanged: (hue) {
              setState(() {
                _selectedColor = _selectedColor.withHue(hue);
              });
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedColor = HSVColor.fromColor(widget.initialColor);
                  });
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(color),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hexLabel(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }
}

class _ToneSaturationValueBoard extends StatelessWidget {
  const _ToneSaturationValueBoard({
    required this.color,
    required this.onChanged,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final markerLeft = color.saturation * size.width;
        final markerTop = (1 - color.value) * size.height;
        final hueColor = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();

        void updateColor(Offset localPosition) {
          final dx = localPosition.dx.clamp(0.0, size.width);
          final dy = localPosition.dy.clamp(0.0, size.height);
          onChanged(
            color
                .withSaturation(dx / size.width)
                .withValue(1 - (dy / size.height)),
          );
        }

        return GestureDetector(
          onTapDown: (details) => updateColor(details.localPosition),
          onPanDown: (details) => updateColor(details.localPosition),
          onPanUpdate: (details) => updateColor(details.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, hueColor],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft.clamp(14.0, size.width - 14.0) - 14,
                  top: markerTop.clamp(14.0, size.height - 14.0) - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.toColor(),
                      border: Border.all(color: Colors.white, width: 2.6),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToneHueSpectrumSlider extends StatelessWidget {
  const _ToneHueSpectrumSlider({
    required this.hue,
    required this.onChanged,
  });

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final markerLeft = (hue / 360) * width;

          void updateHue(Offset localPosition) {
            final dx = localPosition.dx.clamp(0.0, width);
            onChanged((dx / width) * 360);
          }

          return GestureDetector(
            onTapDown: (details) => updateHue(details.localPosition),
            onPanDown: (details) => updateHue(details.localPosition),
            onPanUpdate: (details) => updateHue(details.localPosition),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft.clamp(14.0, width - 14.0) - 14,
                  top: 3,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      border: Border.all(color: Colors.white, width: 2.6),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
