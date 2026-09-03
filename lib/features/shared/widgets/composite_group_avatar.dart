import 'dart:io';

import 'package:flutter/material.dart';

import '../../chats/domain/group_participant.dart';
import 'avatar_badge.dart';

/// WhatsApp-style tiled group icon when no custom photo is set -- up to
/// four member photos/initials fill the circle edge-to-edge with thin gaps.
class CompositeGroupAvatar extends StatelessWidget {
  const CompositeGroupAvatar({
    required this.participants,
    required this.fallbackLabel,
    required this.fallbackColor,
    this.size = 52,
    super.key,
  });

  /// Show at most four members -- enough to read at list-tile sizes without
  /// crowding; larger groups still get a representative sample.
  static const int maxVisibleMembers = 4;

  final List<GroupParticipant> participants;
  final String fallbackLabel;
  final Color fallbackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Your own face is in every group you are in, so it tells you nothing
    // about which group this is -- drop it and let a member who actually
    // distinguishes the group take the tile.
    final members = participants
        .where((participant) => !participant.isSelf)
        .take(maxVisibleMembers)
        .toList(growable: false);
    if (members.isEmpty) {
      return AvatarBadge(
        label: fallbackLabel,
        color: fallbackColor,
        size: size,
      );
    }
    if (members.length == 1) {
      final member = members.first;
      return AvatarBadge(
        label: member.avatarLabel,
        color: member.accentColor,
        avatarUrl: member.avatarUrl,
        size: size,
      );
    }

    final vDivider = _verticalDivider(context);
    final hDivider = _horizontalDivider(context);

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: fallbackColor.withValues(alpha: 0.12),
          child: switch (members.length) {
            2 => Row(
                children: [
                  Expanded(child: _MemberTile(member: members[0])),
                  vDivider,
                  Expanded(child: _MemberTile(member: members[1])),
                ],
              ),
            3 => Row(
                children: [
                  Expanded(child: _MemberTile(member: members[0])),
                  vDivider,
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _MemberTile(member: members[1])),
                        hDivider,
                        Expanded(child: _MemberTile(member: members[2])),
                      ],
                    ),
                  ),
                ],
              ),
            _ => Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _MemberTile(member: members[0])),
                        vDivider,
                        Expanded(child: _MemberTile(member: members[1])),
                      ],
                    ),
                  ),
                  hDivider,
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _MemberTile(member: members[2])),
                        vDivider,
                        Expanded(child: _MemberTile(member: members[3])),
                      ],
                    ),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }

  Widget _verticalDivider(BuildContext context) {
    return Container(
      width: 1,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
    );
  }

  Widget _horizontalDivider(BuildContext context) {
    return Container(
      height: 1,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
    );
  }
}

/// One square cell inside the mosaic -- fills its slot completely instead of
/// a small circle centered in empty space.
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final GroupParticipant member;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final initials = _initials(member.avatarLabel);
        final fontSize = (constraints.maxHeight * 0.34).clamp(10.0, 18.0);

        final fallback = ColoredBox(
          color: member.accentColor.withValues(alpha: 0.22),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: fontSize,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
              ),
            ),
          ),
        );

        final url = member.avatarUrl?.trim();
        if (url == null || url.isEmpty) {
          return fallback;
        }

        final isRemote =
            url.startsWith('http://') || url.startsWith('https://');
        final imageProvider = isRemote
            ? NetworkImage(url)
            : FileImage(File(url)) as ImageProvider;

        return Image(
          image: imageProvider,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        );
      },
    );
  }

  String _initials(String label) {
    final normalized = label.trim().isEmpty ? '?' : label.trim();
    if (normalized.length <= 2) {
      return normalized.toUpperCase();
    }
    return normalized.substring(0, 2).toUpperCase();
  }
}
