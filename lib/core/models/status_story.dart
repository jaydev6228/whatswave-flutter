import 'package:flutter/material.dart';

enum StatusStoryType { text, photo, video }

enum StatusMediaOverlayType { text, emoji, sticker, music }

class StatusMediaTransform {
  const StatusMediaTransform({
    this.scale = 1,
    this.offsetDx = 0,
    this.offsetDy = 0,
    this.rotationQuarterTurns = 0,
    this.frameAspectRatio,
  });

  final double scale;
  final double offsetDx;
  final double offsetDy;
  final int rotationQuarterTurns;
  final double? frameAspectRatio;

  StatusMediaTransform copyWith({
    double? scale,
    double? offsetDx,
    double? offsetDy,
    int? rotationQuarterTurns,
    double? frameAspectRatio,
    bool clearFrameAspectRatio = false,
  }) {
    return StatusMediaTransform(
      scale: scale ?? this.scale,
      offsetDx: offsetDx ?? this.offsetDx,
      offsetDy: offsetDy ?? this.offsetDy,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      frameAspectRatio: clearFrameAspectRatio
          ? null
          : (frameAspectRatio ?? this.frameAspectRatio),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scale': scale,
      'offsetDx': offsetDx,
      'offsetDy': offsetDy,
      'rotationQuarterTurns': rotationQuarterTurns,
      'frameAspectRatio': frameAspectRatio,
    };
  }

  static StatusMediaTransform? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    return StatusMediaTransform(
      scale: (_doubleValueFromRaw(raw['scale']) ?? 1).clamp(0.8, 4.0),
      offsetDx: (_doubleValueFromRaw(raw['offsetDx']) ?? 0).clamp(-1.6, 1.6),
      offsetDy: (_doubleValueFromRaw(raw['offsetDy']) ?? 0).clamp(-1.6, 1.6),
      rotationQuarterTurns:
          (_intValueFromRaw(raw['rotationQuarterTurns']) ?? 0).clamp(-12, 12),
      frameAspectRatio:
          (_doubleValueFromRaw(raw['frameAspectRatio'])?.isFinite ?? false)
              ? (_doubleValueFromRaw(raw['frameAspectRatio'])!).clamp(0.5, 2.2)
              : null,
    );
  }
}

enum StatusTextLayout {
  classic,
  poster,
  banner,
  invitation,
  spotlight,
  note,
}

enum StatusTextAlignment { left, center, right }

class StatusTextStyle {
  const StatusTextStyle({
    this.fontId = 'clean',
    this.backgroundId = 'emerald_pop',
    this.layout = StatusTextLayout.classic,
    this.alignment = StatusTextAlignment.center,
    this.textColorValue,
    this.backgroundColorValue,
    this.useSolidBackground = false,
    this.sizeScale = 1,
  });

  final String fontId;
  final String backgroundId;
  final StatusTextLayout layout;
  final StatusTextAlignment alignment;
  final int? textColorValue;
  final int? backgroundColorValue;
  final bool useSolidBackground;
  final double sizeScale;

  Color? get textColor =>
      textColorValue == null ? null : Color(textColorValue!);
  Color? get backgroundColor =>
      backgroundColorValue == null ? null : Color(backgroundColorValue!);

  StatusTextStyle copyWith({
    String? fontId,
    String? backgroundId,
    StatusTextLayout? layout,
    StatusTextAlignment? alignment,
    int? textColorValue,
    bool clearTextColor = false,
    int? backgroundColorValue,
    bool clearBackgroundColor = false,
    bool? useSolidBackground,
    double? sizeScale,
  }) {
    return StatusTextStyle(
      fontId: fontId ?? this.fontId,
      backgroundId: backgroundId ?? this.backgroundId,
      layout: layout ?? this.layout,
      alignment: alignment ?? this.alignment,
      textColorValue:
          clearTextColor ? null : (textColorValue ?? this.textColorValue),
      backgroundColorValue: clearBackgroundColor
          ? null
          : (backgroundColorValue ?? this.backgroundColorValue),
      useSolidBackground: useSolidBackground ?? this.useSolidBackground,
      sizeScale: sizeScale ?? this.sizeScale,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fontId': fontId,
      'backgroundId': backgroundId,
      'layout': layout.name,
      'alignment': alignment.name,
      'textColorValue': textColorValue,
      'backgroundColorValue': backgroundColorValue,
      'useSolidBackground': useSolidBackground,
      'sizeScale': sizeScale,
    };
  }

  static StatusTextStyle? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final fontId = raw['fontId'];
    final backgroundId = raw['backgroundId'];
    final layout = _statusTextLayoutFromRaw(raw['layout']);
    final alignment = _statusTextAlignmentFromRaw(raw['alignment']);
    if (fontId is! String ||
        backgroundId is! String ||
        layout == null ||
        alignment == null) {
      return null;
    }

    final sizeScale = _doubleValueFromRaw(raw['sizeScale']) ?? 1;
    return StatusTextStyle(
      fontId: fontId,
      backgroundId: backgroundId,
      layout: layout,
      alignment: alignment,
      textColorValue: _intValueFromRaw(raw['textColorValue']),
      backgroundColorValue: _intValueFromRaw(raw['backgroundColorValue']),
      useSolidBackground: raw['useSolidBackground'] == true,
      sizeScale: sizeScale.clamp(0.72, 1.45),
    );
  }
}

class StatusMusicTrack {
  const StatusMusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.colorValue,
    this.secondaryColorValue,
    this.previewAssetPath,
    this.bannerStyleId = 'cover',
  });

  final String id;
  final String title;
  final String artist;
  final int? colorValue;
  final int? secondaryColorValue;
  final String? previewAssetPath;
  final String bannerStyleId;

  Color? get color => colorValue == null ? null : Color(colorValue!);
  Color? get secondaryColor =>
      secondaryColorValue == null ? null : Color(secondaryColorValue!);

  StatusMusicTrack copyWith({
    String? id,
    String? title,
    String? artist,
    int? colorValue,
    int? secondaryColorValue,
    String? previewAssetPath,
    String? bannerStyleId,
    bool clearColor = false,
    bool clearSecondaryColor = false,
    bool clearPreviewAssetPath = false,
  }) {
    return StatusMusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      secondaryColorValue: clearSecondaryColor
          ? null
          : (secondaryColorValue ?? this.secondaryColorValue),
      previewAssetPath: clearPreviewAssetPath
          ? null
          : (previewAssetPath ?? this.previewAssetPath),
      bannerStyleId: bannerStyleId ?? this.bannerStyleId,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'artist': artist,
      'colorValue': colorValue,
      'secondaryColorValue': secondaryColorValue,
      'previewAssetPath': previewAssetPath,
      'bannerStyleId': bannerStyleId,
    };
  }

  static StatusMusicTrack? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final id = raw['id'];
    final title = raw['title'];
    final artist = raw['artist'];
    if (id is! String || title is! String || artist is! String) {
      return null;
    }

    return StatusMusicTrack(
      id: id,
      title: title,
      artist: artist,
      colorValue: _colorValueFromRaw(raw['colorValue']),
      secondaryColorValue: _colorValueFromRaw(raw['secondaryColorValue']),
      previewAssetPath: raw['previewAssetPath'] is String &&
              (raw['previewAssetPath'] as String).isNotEmpty
          ? raw['previewAssetPath'] as String
          : null,
      bannerStyleId: raw['bannerStyleId'] is String &&
              (raw['bannerStyleId'] as String).isNotEmpty
          ? raw['bannerStyleId'] as String
          : 'cover',
    );
  }
}

class StatusMediaOverlayItem {
  const StatusMediaOverlayItem({
    required this.id,
    required this.type,
    required this.label,
    this.subtitle,
    this.positionDx = 0.5,
    this.positionDy = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.textStyle,
    this.accentColorValue,
    this.secondaryColorValue,
    this.variantId,
  });

  final String id;
  final StatusMediaOverlayType type;
  final String label;
  final String? subtitle;
  final double positionDx;
  final double positionDy;
  final double scale;
  final double rotation;
  final StatusTextStyle? textStyle;
  final int? accentColorValue;
  final int? secondaryColorValue;
  final String? variantId;

  Color? get accentColor =>
      accentColorValue == null ? null : Color(accentColorValue!);
  Color? get secondaryColor =>
      secondaryColorValue == null ? null : Color(secondaryColorValue!);

  bool get isTextual => type == StatusMediaOverlayType.text;

  StatusMediaOverlayItem copyWith({
    String? id,
    StatusMediaOverlayType? type,
    String? label,
    String? subtitle,
    bool clearSubtitle = false,
    double? positionDx,
    double? positionDy,
    double? scale,
    double? rotation,
    StatusTextStyle? textStyle,
    bool clearTextStyle = false,
    int? accentColorValue,
    bool clearAccentColor = false,
    int? secondaryColorValue,
    bool clearSecondaryColor = false,
    String? variantId,
    bool clearVariantId = false,
  }) {
    return StatusMediaOverlayItem(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      positionDx: positionDx ?? this.positionDx,
      positionDy: positionDy ?? this.positionDy,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      textStyle: clearTextStyle ? null : (textStyle ?? this.textStyle),
      accentColorValue:
          clearAccentColor ? null : (accentColorValue ?? this.accentColorValue),
      secondaryColorValue: clearSecondaryColor
          ? null
          : (secondaryColorValue ?? this.secondaryColorValue),
      variantId: clearVariantId ? null : (variantId ?? this.variantId),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'label': label,
      'subtitle': subtitle,
      'positionDx': positionDx,
      'positionDy': positionDy,
      'scale': scale,
      'rotation': rotation,
      'textStyle': textStyle?.toJson(),
      'accentColorValue': accentColorValue,
      'secondaryColorValue': secondaryColorValue,
      'variantId': variantId,
    };
  }

  static StatusMediaOverlayItem? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final id = raw['id'];
    final type = _statusMediaOverlayTypeFromRaw(raw['type']);
    final label = raw['label'];
    if (id is! String || type == null || label is! String || label.isEmpty) {
      return null;
    }

    final positionDx =
        (_doubleValueFromRaw(raw['positionDx']) ?? 0.5).clamp(0.04, 0.96);
    final positionDy =
        (_doubleValueFromRaw(raw['positionDy']) ?? 0.5).clamp(0.04, 0.96);
    final scale = (_doubleValueFromRaw(raw['scale']) ?? 1).clamp(0.55, 3.0);
    final rotation = _doubleValueFromRaw(raw['rotation']) ?? 0;

    return StatusMediaOverlayItem(
      id: id,
      type: type,
      label: label,
      subtitle:
          raw['subtitle'] is String && (raw['subtitle'] as String).isNotEmpty
              ? raw['subtitle'] as String
              : null,
      positionDx: positionDx,
      positionDy: positionDy,
      scale: scale,
      rotation: rotation,
      textStyle: StatusTextStyle.fromJson(raw['textStyle']),
      accentColorValue: _colorValueFromRaw(raw['accentColorValue']),
      secondaryColorValue: _colorValueFromRaw(raw['secondaryColorValue']),
      variantId:
          raw['variantId'] is String && (raw['variantId'] as String).isNotEmpty
              ? raw['variantId'] as String
              : null,
    );
  }
}

class StatusStorySegment {
  const StatusStorySegment({
    required this.id,
    required this.type,
    required this.previewText,
    this.localMediaPath,
    this.mediaTransform = const StatusMediaTransform(),
    this.durationMillis,
    this.textStyle,
    this.emoji,
    this.stickers = const <String>[],
    this.musicTrack,
    this.overlayItems = const <StatusMediaOverlayItem>[],
  });

  final String id;
  final StatusStoryType type;
  final String previewText;
  final String? localMediaPath;
  final StatusMediaTransform mediaTransform;
  final int? durationMillis;
  final StatusTextStyle? textStyle;
  final String? emoji;
  final List<String> stickers;
  final StatusMusicTrack? musicTrack;
  final List<StatusMediaOverlayItem> overlayItems;

  bool get hasLocalMedia => localMediaPath?.trim().isNotEmpty == true;
  bool get hasRichOverlays => overlayItems.isNotEmpty;

  StatusStorySegment copyWith({
    String? id,
    StatusStoryType? type,
    String? previewText,
    String? localMediaPath,
    StatusMediaTransform? mediaTransform,
    int? durationMillis,
    StatusTextStyle? textStyle,
    bool clearTextStyle = false,
    String? emoji,
    bool clearEmoji = false,
    List<String>? stickers,
    StatusMusicTrack? musicTrack,
    bool clearMusicTrack = false,
    List<StatusMediaOverlayItem>? overlayItems,
  }) {
    return StatusStorySegment(
      id: id ?? this.id,
      type: type ?? this.type,
      previewText: previewText ?? this.previewText,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      mediaTransform: mediaTransform ?? this.mediaTransform,
      durationMillis: durationMillis ?? this.durationMillis,
      textStyle: clearTextStyle ? null : (textStyle ?? this.textStyle),
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
      stickers: List<String>.unmodifiable(stickers ?? this.stickers),
      musicTrack: clearMusicTrack ? null : (musicTrack ?? this.musicTrack),
      overlayItems: List<StatusMediaOverlayItem>.unmodifiable(
        overlayItems ?? this.overlayItems,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'previewText': previewText,
      'localMediaPath': localMediaPath,
      'mediaTransform': mediaTransform.toJson(),
      'durationMillis': durationMillis,
      'textStyle': textStyle?.toJson(),
      'emoji': emoji,
      'stickers': stickers,
      'musicTrack': musicTrack?.toJson(),
      'overlayItems': overlayItems
          .map((overlay) => overlay.toJson())
          .toList(growable: false),
    };
  }

  static StatusStorySegment? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final id = raw['id'];
    final type = _statusStoryTypeFromRaw(raw['type']);
    final previewText = raw['previewText'];
    if (id is! String || type == null || previewText is! String) {
      return null;
    }

    final localMediaPath = raw['localMediaPath'];
    final mediaTransform =
        StatusMediaTransform.fromJson(raw['mediaTransform']) ??
            const StatusMediaTransform();
    final durationMillis = raw['durationMillis'];
    final textStyle = StatusTextStyle.fromJson(raw['textStyle']);
    final stickers = _stringListFromRaw(raw['stickers']);
    final musicTrack = StatusMusicTrack.fromJson(raw['musicTrack']);
    final overlayItems = <StatusMediaOverlayItem>[
      for (final entry in _overlayListFromRaw(raw['overlayItems']))
        if (StatusMediaOverlayItem.fromJson(entry) case final overlay?) overlay,
    ];
    return StatusStorySegment(
      id: id,
      type: type,
      previewText: previewText,
      localMediaPath: localMediaPath is String && localMediaPath.isNotEmpty
          ? localMediaPath
          : null,
      mediaTransform: mediaTransform,
      durationMillis: switch (durationMillis) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      },
      textStyle: textStyle,
      emoji: raw['emoji'] is String && (raw['emoji'] as String).isNotEmpty
          ? raw['emoji'] as String
          : null,
      stickers: List<String>.unmodifiable(stickers),
      musicTrack: musicTrack,
      overlayItems: List<StatusMediaOverlayItem>.unmodifiable(overlayItems),
    );
  }
}

class StatusStory {
  const StatusStory({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.previewText,
    required this.timeLabel,
    required this.accentColor,
    this.type = StatusStoryType.text,
    this.isMine = false,
    this.totalSegments = 1,
    this.seenSegments = 0,
    this.segments = const <StatusStorySegment>[],
  });

  final String id;
  final String name;
  final String avatarLabel;
  final String previewText;
  final String timeLabel;
  final Color accentColor;
  final StatusStoryType type;
  final bool isMine;
  final int totalSegments;
  final int seenSegments;
  final List<StatusStorySegment> segments;

  bool get hasSegments => totalSegments > 0;
  int get clampedSeenSegments =>
      hasSegments ? seenSegments.clamp(0, totalSegments).toInt() : 0;
  bool get hasUnseenSegments =>
      hasSegments && clampedSeenSegments < totalSegments;
  StatusStorySegment? get latestSegment =>
      segments.isEmpty ? null : segments.last;

  StatusStorySegment? segmentAt(int index) {
    if (index < 0 || index >= totalSegments) {
      return null;
    }

    if (segments.isNotEmpty && index < segments.length) {
      return segments[index];
    }

    return StatusStorySegment(
      id: '$id-segment-$index',
      type: type,
      previewText: index == 0 ? previewText : '',
    );
  }

  StatusStory copyWith({
    String? id,
    String? name,
    String? avatarLabel,
    String? previewText,
    String? timeLabel,
    Color? accentColor,
    StatusStoryType? type,
    bool? isMine,
    int? totalSegments,
    int? seenSegments,
    List<StatusStorySegment>? segments,
  }) {
    return StatusStory(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      previewText: previewText ?? this.previewText,
      timeLabel: timeLabel ?? this.timeLabel,
      accentColor: accentColor ?? this.accentColor,
      type: type ?? this.type,
      isMine: isMine ?? this.isMine,
      totalSegments: totalSegments ?? this.totalSegments,
      seenSegments: seenSegments ?? this.seenSegments,
      segments: List<StatusStorySegment>.unmodifiable(
        segments ?? this.segments,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'avatarLabel': avatarLabel,
      'previewText': previewText,
      'timeLabel': timeLabel,
      'accentColor': accentColor.toARGB32(),
      'type': type.name,
      'isMine': isMine,
      'totalSegments': totalSegments,
      'seenSegments': seenSegments,
      'segments':
          segments.map((segment) => segment.toJson()).toList(growable: false),
    };
  }

  static StatusStory? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final id = raw['id'];
    final name = raw['name'];
    final avatarLabel = raw['avatarLabel'];
    final previewText = raw['previewText'];
    final timeLabel = raw['timeLabel'];
    final accentColorValue = _colorValueFromRaw(raw['accentColor']);
    final type = _statusStoryTypeFromRaw(raw['type']);
    if (id is! String ||
        name is! String ||
        avatarLabel is! String ||
        previewText is! String ||
        timeLabel is! String ||
        accentColorValue == null ||
        type == null) {
      return null;
    }

    final segments = <StatusStorySegment>[
      for (final entry in _segmentListFromRaw(raw['segments']))
        if (StatusStorySegment.fromJson(entry) case final segment?) segment,
    ];
    final rawTotalSegments = _intValueFromRaw(raw['totalSegments']);
    final totalSegments = segments.isNotEmpty
        ? segments.length
        : (rawTotalSegments ?? 1).clamp(0, 12).toInt();
    return StatusStory(
      id: id,
      name: name,
      avatarLabel: avatarLabel,
      previewText: previewText,
      timeLabel: timeLabel,
      accentColor: Color(accentColorValue),
      type: type,
      isMine: raw['isMine'] == true,
      totalSegments: totalSegments,
      seenSegments: (_intValueFromRaw(raw['seenSegments']) ?? 0)
          .clamp(0, totalSegments)
          .toInt(),
      segments: List<StatusStorySegment>.unmodifiable(segments),
    );
  }
}

StatusStoryType? _statusStoryTypeFromRaw(Object? raw) {
  if (raw is StatusStoryType) {
    return raw;
  }

  if (raw is String) {
    for (final value in StatusStoryType.values) {
      if (value.name == raw) {
        return value;
      }
    }
  }

  if (raw is int && raw >= 0 && raw < StatusStoryType.values.length) {
    return StatusStoryType.values[raw];
  }

  return null;
}

StatusMediaOverlayType? _statusMediaOverlayTypeFromRaw(Object? raw) {
  if (raw is StatusMediaOverlayType) {
    return raw;
  }

  if (raw is String) {
    for (final value in StatusMediaOverlayType.values) {
      if (value.name == raw) {
        return value;
      }
    }
  }

  if (raw is int && raw >= 0 && raw < StatusMediaOverlayType.values.length) {
    return StatusMediaOverlayType.values[raw];
  }

  return null;
}

StatusTextLayout? _statusTextLayoutFromRaw(Object? raw) {
  if (raw is StatusTextLayout) {
    return raw;
  }

  if (raw is String) {
    for (final value in StatusTextLayout.values) {
      if (value.name == raw) {
        return value;
      }
    }
  }

  if (raw is int && raw >= 0 && raw < StatusTextLayout.values.length) {
    return StatusTextLayout.values[raw];
  }

  return null;
}

StatusTextAlignment? _statusTextAlignmentFromRaw(Object? raw) {
  if (raw is StatusTextAlignment) {
    return raw;
  }

  if (raw is String) {
    for (final value in StatusTextAlignment.values) {
      if (value.name == raw) {
        return value;
      }
    }
  }

  if (raw is int && raw >= 0 && raw < StatusTextAlignment.values.length) {
    return StatusTextAlignment.values[raw];
  }

  return null;
}

List<Object?> _segmentListFromRaw(Object? raw) {
  if (raw is List<Object?>) {
    return raw;
  }
  if (raw is List<dynamic>) {
    return raw;
  }
  return const <Object?>[];
}

List<Object?> _overlayListFromRaw(Object? raw) {
  if (raw is List<Object?>) {
    return raw;
  }
  if (raw is List<dynamic>) {
    return raw;
  }
  return const <Object?>[];
}

List<String> _stringListFromRaw(Object? raw) {
  if (raw is! List) {
    return const <String>[];
  }

  return List<String>.unmodifiable(
    raw.whereType<String>().where((entry) => entry.trim().isNotEmpty),
  );
}

int? _intValueFromRaw(Object? raw) {
  return switch (raw) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
}

double? _doubleValueFromRaw(Object? raw) {
  return switch (raw) {
    double value => value,
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
}

int? _colorValueFromRaw(Object? raw) {
  return switch (raw) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
}
