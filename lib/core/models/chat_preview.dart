import 'package:flutter/material.dart';

enum DeliveryState { sent, delivered, read }

class ChatPreview {
  const ChatPreview({
    required this.name,
    required this.lastMessage,
    required this.timeLabel,
    required this.avatarLabel,
    required this.accentColor,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isGroup = false,
    this.isTyping = false,
    this.hasStory = false,
    this.deliveryState = DeliveryState.delivered,
  });

  final String name;
  final String lastMessage;
  final String timeLabel;
  final String avatarLabel;
  final Color accentColor;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isGroup;
  final bool isTyping;
  final bool hasStory;
  final DeliveryState deliveryState;
}
