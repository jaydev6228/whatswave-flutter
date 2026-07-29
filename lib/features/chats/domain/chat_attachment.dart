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
  });

  final String id;
  final ChatAttachmentType type;
  final String title;
  final String details;
  final Color tintColor;
  final double aspectRatio;

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
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      details: details ?? this.details,
      tintColor: tintColor ?? this.tintColor,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}
