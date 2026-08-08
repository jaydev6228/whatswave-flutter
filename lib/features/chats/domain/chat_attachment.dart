import 'package:flutter/material.dart';

enum ChatAttachmentType { photo, video, file, location, voiceNote }

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.tintColor,
    this.aspectRatio = 1.25,
    this.latitude,
    this.longitude,
    this.localMediaPath,
  });

  final String id;
  final ChatAttachmentType type;
  final String title;
  final String details;
  final Color tintColor;
  final double aspectRatio;

  /// Set only for [ChatAttachmentType.location] messages carrying a real
  /// device fix -- null for every other attachment type.
  final double? latitude;
  final double? longitude;

  /// A real device-local photo/video path (or a bundled `asset://` path),
  /// set only for [ChatAttachmentType.photo]/[ChatAttachmentType.video]
  /// attachments picked from the device. Local-only -- this project has no
  /// Firebase Storage configured, so the media renders on the sending
  /// device but does not sync to the other participant. Null falls back to
  /// [tintColor] as a plain placeholder swatch.
  final String? localMediaPath;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get compactLabel {
    return switch (type) {
      ChatAttachmentType.photo => 'Photo',
      ChatAttachmentType.video =>
        details.trim().isEmpty ? 'Video' : 'Video · ${details.trim()}',
      ChatAttachmentType.file =>
        title.trim().isEmpty ? 'File' : 'File · ${title.trim()}',
      ChatAttachmentType.location =>
        title.trim().isEmpty ? 'Location' : 'Location · ${title.trim()}',
      ChatAttachmentType.voiceNote => details.trim().isEmpty
          ? 'Voice note'
          : 'Voice note · ${details.trim()}',
    };
  }

  ChatAttachment copyWith({
    String? id,
    ChatAttachmentType? type,
    String? title,
    String? details,
    Color? tintColor,
    double? aspectRatio,
    double? latitude,
    double? longitude,
    String? localMediaPath,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      details: details ?? this.details,
      tintColor: tintColor ?? this.tintColor,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      localMediaPath: localMediaPath ?? this.localMediaPath,
    );
  }
}
