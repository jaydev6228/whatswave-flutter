import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../app/theme/app_palette.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/liquid_glass.dart';
import '../application/calls_controller.dart';
import '../domain/call_contact.dart';
import '../domain/call_session.dart';
import '../domain/group_call_participant.dart';
import 'call_participant_avatar.dart';
import 'group_call_presence_bubbles.dart';

const Alignment _audioFallbackStageAlignment = Alignment(0, -0.08);

/// For a 2-participant group call, the counterpart to show full-screen --
/// mirrors a regular 1:1 call rather than a cramped 2-tile grid.
GroupCallParticipantView? _otherGroupParticipant(
  List<GroupCallParticipantView> participants,
) {
  for (final participant in participants) {
    if (!participant.isSelf) {
      return participant;
    }
  }
  return participants.isEmpty ? null : participants.first;
}

class CallExperienceScreen extends StatefulWidget {
  const CallExperienceScreen({
    required this.controller,
    super.key,
  });

  final CallsController controller;

  @override
  State<CallExperienceScreen> createState() => _CallExperienceScreenState();
}

class _CallExperienceScreenState extends State<CallExperienceScreen> {
  CallSession? _lastKnownSession;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _lastKnownSession = widget.controller.currentSession;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final session = widget.controller.currentSession;
    if (session != null) {
      final previous = _lastKnownSession;
      _lastKnownSession = session;
      if (!mounted) {
        return;
      }
      if (previous != null && identical(previous, session)) {
        return;
      }
      setState(() {});
      return;
    }

    if (_isClosing || !mounted) {
      return;
    }
    _isClosing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.currentSession ?? _lastKnownSession;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final gradient = _backgroundGradient(context, session);
    final videoBackdropColor =
        session.isVideo ? Colors.black : gradient.colors.first;

    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('call_experience_screen'),
        backgroundColor: videoBackdropColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (session.isVideo)
              const ColoredBox(color: Colors.black)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: gradient,
                ),
              ),
            // Remote video/ambient stage now paints edge-to-edge, behind
            // the safe-area-padded chrome below -- "show opponent video to
            // whole screen behind element on screen". Audio calls have no
            // video layer; _AudioCallLayout's own backdrop covers that
            // case entirely within the padded content.
            if (session.isVideo)
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final liveSession =
                      widget.controller.currentSession ?? session;
                  return _VideoAmbientStage(
                    key: const Key('call_video_ambient_stage'),
                    controller: widget.controller,
                    session: liveSession,
                    compact: _isCompactLayout(context),
                    scheme: _callVisualScheme(context, liveSession),
                  );
                },
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: session.isVideo
                    ? ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final liveSession =
                              widget.controller.currentSession ?? session;
                          return _VideoCallLayout(
                            controller: widget.controller,
                            session: liveSession,
                          );
                        },
                      )
                    : _AudioCallLayout(
                        controller: widget.controller,
                        session: session,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCallLayout extends StatelessWidget {
  const _VideoCallLayout({
    required this.controller,
    required this.session,
  });

  final CallsController controller;
  final CallSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = _callVisualScheme(context, session);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactWidth = constraints.maxWidth < 390;
        final isCompactHeight = constraints.maxHeight < 760;
        final isCompact = isCompactWidth || isCompactHeight;
        final previewWidth = isCompactWidth ? 116.0 : 144.0;
        final previewHeight = isCompactHeight ? 170.0 : 212.0;
        final previewMargin = isCompact ? 16.0 : 24.0;
        final textColor = scheme.primaryText;
        final isConnected = session.phase == CallSessionPhase.connected;
        final isGroupVideo = session.contact.isGroup;
        final groupParticipants = isGroupVideo
            ? controller.groupCallParticipants
            : const <GroupCallParticipantView>[];
        // A 2-person group call gets the same full-screen-remote +
        // PiP-local chrome as a real 1:1 call instead of a cramped 2-tile
        // grid -- it *is* effectively a 1:1 call at that point.
        final isTwoPersonGroupVideo =
            isGroupVideo && groupParticipants.length == 2;
        final showOneOnOneChrome = !isGroupVideo || isTwoPersonGroupVideo;
        final headerName = isTwoPersonGroupVideo
            ? _otherGroupParticipant(groupParticipants)?.displayName ??
                session.contact.name
            : session.contact.name;

        // Chrome overlaid on top of the full-screen remote video behind
        // this (see _CallExperienceScreenState.build). No "Video call"
        // pill or name/status header while ringing/connecting/incoming --
        // _VideoAmbientStage's own centered avatar+name+status overlay
        // already covers that; showing both was the reported redundant
        // duplicate label. Once connected, a small name+duration label
        // takes its place (real info, not a repeat of "you're on a video
        // call").
        return Stack(
          children: [
            if (isConnected && showOneOnOneChrome)
              Positioned(
                top: 0,
                left: 0,
                right: previewWidth + previewMargin + 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayCallName(headerName),
                      key: const Key('call_name_text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _videoStatusText(session),
                      key: const Key('call_video_status_text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            if (showOneOnOneChrome)
              Positioned(
                top: previewMargin,
                right: previewMargin,
                child: _LocalVideoPreviewCard(
                  session: session,
                  localVideoTrack:
                      session.isReal ? controller.localVideoTrack : null,
                  width: previewWidth,
                  height: previewHeight,
                  compact: isCompact,
                  scheme: scheme,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: session.phase == CallSessionPhase.incoming
                  ? _IncomingCallActions(
                      controller: controller,
                      session: session,
                      textColor: textColor,
                    )
                  : Align(
                      alignment: Alignment.bottomCenter,
                      child: _VideoControlDock(
                        controller: controller,
                        session: session,
                        compact: isCompact,
                        scheme: scheme,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AudioCallLayout extends StatelessWidget {
  const _AudioCallLayout({
    required this.controller,
    required this.session,
  });

  final CallsController controller;
  final CallSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = _callVisualScheme(context, session);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxHeight < 760 || constraints.maxWidth < 390;
        final textColor = scheme.primaryText;
        final isGroupCall = session.contact.isGroup;
        final playfieldTopPad = isCompact ? 98.0 : 108.0;
        final playfieldBottomPad = isCompact ? 12.0 : 16.0;
        final headerTop = isCompact ? 24.0 : 32.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AudioCenterStage(
                        controller: controller,
                        session: session,
                        compact: isCompact,
                        scheme: scheme,
                        isGroupCall: isGroupCall,
                      ),
                      if (isGroupCall)
                        GroupCallFloatingFieldHost(
                          controller: controller,
                          compact: isCompact,
                          primaryText: scheme.primaryText,
                          surfaceColor: scheme.identitySurfaceColor,
                          ringColor: scheme.avatarMiddleColor,
                          topPadding: playfieldTopPad,
                          bottomPadding: playfieldBottomPad,
                        ),
                    ],
                  ),
                ),
                if (session.phase == CallSessionPhase.incoming)
                  _IncomingCallActions(
                    controller: controller,
                    session: session,
                    textColor: textColor,
                  )
                else
                  _AudioCallActions(
                    controller: controller,
                    session: session,
                    compact: isCompact,
                    scheme: scheme,
                  ),
              ],
            ),
            Positioned(
              top: headerTop,
              left: 0,
              right: 0,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final detailText = session.phase == CallSessionPhase.connected
                      ? _formatDuration(session.elapsedSeconds(DateTime.now()))
                      : _audioStatusText(session);
                  final detailStyle =
                      session.phase == CallSessionPhase.connected
                          ? theme.textTheme.headlineLarge?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              fontSize: isCompact ? 34 : 38,
                            )
                          : theme.textTheme.titleLarge?.copyWith(
                              color: scheme.secondaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: isCompact ? 22 : 24,
                            );
                  return Column(
                    children: [
                      Text(
                        _displayCallName(session.contact.name),
                        key: const Key('call_name_text'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: isCompact ? 42 : 48,
                          letterSpacing: -0.9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detailText,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VideoAmbientStage extends StatelessWidget {
  const _VideoAmbientStage({
    super.key,
    required this.controller,
    required this.session,
    required this.compact,
    required this.scheme,
  });

  final CallsController controller;
  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final accentColor = session.contact.accentColor;
    final secondaryGlow = Color.lerp(AppPalette.sky, AppPalette.purple, 0.55)!;
    final isGroupVideo = session.contact.isGroup;
    final groupParticipants = isGroupVideo
        ? controller.groupCallParticipants
        : const <GroupCallParticipantView>[];
    // A 2-person group call reads as a real 1:1 call: full-screen the
    // other participant (with their own camera-off fallback) instead of
    // splitting the screen into a cramped 2-tile grid.
    final isTwoPersonGroupVideo = isGroupVideo && groupParticipants.length == 2;
    final otherParticipant = isTwoPersonGroupVideo
        ? _otherGroupParticipant(groupParticipants)
        : null;
    final showGroupVideoGrid = isGroupVideo && !isTwoPersonGroupVideo;
    final remoteTrack = session.isReal ? controller.remoteVideoTrack : null;
    final showRemoteVideo = !isGroupVideo &&
        session.phase == CallSessionPhase.connected &&
        remoteTrack != null;
    final showTwoPersonRemoteTile = isTwoPersonGroupVideo &&
        session.phase == CallSessionPhase.connected &&
        otherParticipant != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!showGroupVideoGrid) ...[
          Align(
            alignment: const Alignment(-0.92, -0.08),
            child: _AmbientGlow(
              size: compact ? 250 : 320,
              color: accentColor.withValues(alpha: scheme.isDark ? 0.2 : 0.11),
            ),
          ),
          Align(
            alignment: const Alignment(0.96, 0.34),
            child: _AmbientGlow(
              size: compact ? 280 : 340,
              color:
                  secondaryGlow.withValues(alpha: scheme.isDark ? 0.18 : 0.1),
            ),
          ),
          Align(
            alignment: const Alignment(0.04, 0.02),
            child: _AmbientGlow(
              size: compact ? 160 : 210,
              color:
                  (scheme.isDark ? Colors.white : AppPalette.cloud).withValues(
                alpha: scheme.isDark ? 0.06 : 0.52,
              ),
            ),
          ),
        ],
        if (showGroupVideoGrid)
          Positioned.fill(
            key: const Key('call_group_video_grid'),
            child: _GroupCallVideoGrid(
              controller: controller,
              session: session,
              scheme: scheme,
            ),
          )
        else if (showTwoPersonRemoteTile)
          Positioned.fill(
            key: const Key('call_group_two_person_remote_tile'),
            child: _GroupCallVideoTile(
              participant: otherParticipant,
              track: controller.remoteVideoTracksByUid[otherParticipant.uid],
              scheme: scheme,
              showBorder: false,
            ),
          )
        else if (showRemoteVideo)
          Positioned.fill(
            key: const Key('call_remote_video_surface'),
            child: lk.VideoTrackRenderer(
              remoteTrack,
              fit: lk.VideoViewFit.cover,
            ),
          )
        else if (session.phase != CallSessionPhase.connected)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CallIdentityAvatar(
                    contact: session.contact,
                    size: compact ? 82 : 94,
                    backgroundColor: scheme.identitySurfaceColor,
                    foregroundColor: scheme.primaryText,
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  // The sole name+status display while ringing/connecting/
                  // incoming -- _VideoCallLayout intentionally shows
                  // nothing up top during these phases so there's exactly
                  // one place showing this, not two.
                  Text(
                    _displayCallName(session.contact.name),
                    key: const Key('call_name_text'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: scheme.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  SizedBox(height: compact ? 6 : 8),
                  Text(
                    _remoteVideoStageLabel(session),
                    key: const Key('call_video_status_text'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LocalVideoPreviewCard extends StatelessWidget {
  const _LocalVideoPreviewCard({
    required this.session,
    required this.width,
    required this.height,
    required this.compact,
    required this.scheme,
    this.localVideoTrack,
  });

  final CallSession session;
  final lk.LocalVideoTrack? localVideoTrack;
  final double width;
  final double height;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(compact ? 26 : 30);

    return SizedBox(
      key: const Key('call_video_preview_card'),
      width: width,
      height: height,
      child: _FrostedPanel(
        borderRadius: borderRadius,
        backgroundColor: scheme.panelBackground,
        borderColor: scheme.panelBorder,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    colors: session.isLocalVideoEnabled
                        ? [
                            scheme.isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.18),
                            AppPalette.sky.withValues(
                              alpha: scheme.isDark ? 0.16 : 0.18,
                            ),
                            AppPalette.purple.withValues(
                              alpha: scheme.isDark ? 0.2 : 0.16,
                            ),
                          ]
                        : [
                            (scheme.isDark ? Colors.black : AppPalette.ink)
                                .withValues(alpha: scheme.isDark ? 0.24 : 0.12),
                            (scheme.isDark ? Colors.black : AppPalette.slate)
                                .withValues(alpha: scheme.isDark ? 0.42 : 0.18),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            // No inset padding here (was 10-12px on all sides) -- the
            // video should touch this card's own edges directly, per the
            // "touch to edged of that view" request. The switch-camera
            // button below gets its own small margin separately, so it
            // doesn't look glued to the exact corner pixel.
            Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: localVideoTrack != null &&
                            session.isLocalVideoEnabled
                        ? ClipRRect(
                            key: const Key('call_local_video_surface'),
                            borderRadius: borderRadius,
                            child: lk.VideoTrackRenderer(
                              localVideoTrack!,
                              fit: lk.VideoViewFit.cover,
                            ),
                          )
                        : session.isLocalVideoEnabled
                            ? Icon(
                                key: const Key('call_local_video_enabled_icon'),
                                Icons.person_pin_circle_outlined,
                                color: scheme.primaryText,
                                size: compact ? 46 : 50,
                              )
                            : Column(
                                key: const Key(
                                    'call_local_video_disabled_panel'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.videocam_off_rounded,
                                    color: scheme.primaryText,
                                    size: compact ? 40 : 44,
                                  ),
                                  SizedBox(height: compact ? 8 : 10),
                                  Text(
                                    'Camera off',
                                    key: const Key(
                                        'call_local_video_status_label'),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: scheme.primaryText,
                                          fontWeight: FontWeight.w700,
                                          fontSize: compact ? 13 : 14,
                                        ),
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioCenterStage extends StatelessWidget {
  const _AudioCenterStage({
    required this.controller,
    required this.session,
    required this.compact,
    required this.scheme,
    required this.isGroupCall,
  });

  final CallsController controller;
  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;
  final bool isGroupCall;

  @override
  Widget build(BuildContext context) {
    final hasPhotoBackdrop = session.contact.photoAssetPath != null;
    final centerStage = isGroupCall
        ? GroupCallCenterAnchorHost(
            controller: controller,
            compact: compact,
            primaryText: scheme.primaryText,
            surfaceColor: scheme.identitySurfaceColor,
            ringColor: scheme.avatarMiddleColor,
          )
        : _AudioAvatarStage(
            session: session,
            compact: compact,
            scheme: scheme,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        compact ? 18 : 24,
        0,
        compact ? 20 : 28,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _AudioPortraitBackdrop(
              session: session,
              compact: compact,
              scheme: scheme,
              fallbackForeground: hasPhotoBackdrop ? null : centerStage,
            ),
          ),
          if (hasPhotoBackdrop)
            Align(
              alignment: _audioFallbackStageAlignment,
              child: centerStage,
            ),
        ],
      ),
    );
  }
}

class _AudioPortraitBackdrop extends StatelessWidget {
  const _AudioPortraitBackdrop({
    required this.session,
    required this.compact,
    required this.scheme,
    this.fallbackForeground,
  });

  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;
  final Widget? fallbackForeground;

  @override
  Widget build(BuildContext context) {
    final accent = session.contact.accentColor;
    final secondaryGlow = Color.lerp(accent, AppPalette.green, 0.35)!;
    final hasPhotoBackdrop = session.contact.photoAssetPath != null;

    return IgnorePointer(
      key: const Key('call_audio_backdrop'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final backdropWidth = hasPhotoBackdrop
              ? (compact
                  ? constraints.maxWidth * 0.72
                  : constraints.maxWidth * 0.78)
              : (constraints.maxWidth * (compact ? 0.56 : 0.62))
                  .clamp(188.0, 270.0)
                  .toDouble();
          final backdropHeight = hasPhotoBackdrop
              ? (compact
                  ? constraints.maxHeight * 0.54
                  : constraints.maxHeight * 0.6)
              : backdropWidth;

          return Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhotoBackdrop)
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: Opacity(
                    opacity: scheme.isDark ? 0.18 : 0.14,
                    child: _BackdropPhotoLayer(
                      contact: session.contact,
                      width: backdropWidth,
                      height: backdropHeight,
                      isDark: scheme.isDark,
                    ),
                  ),
                ),
              if (!hasPhotoBackdrop && fallbackForeground != null)
                Align(
                  alignment: _audioFallbackStageAlignment,
                  child: _AudioFallbackStage(
                    width: backdropWidth,
                    height: backdropHeight,
                    accentColor: accent,
                    isDark: scheme.isDark,
                    foreground: fallbackForeground!,
                  ),
                ),
              Align(
                alignment: const Alignment(-0.7, -0.42),
                child: _AmbientGlow(
                  size: compact ? 112 : 138,
                  color: accent.withValues(alpha: scheme.isDark ? 0.12 : 0.05),
                ),
              ),
              Align(
                alignment: const Alignment(0.7, 0.02),
                child: _AmbientGlow(
                  size: compact ? 120 : 150,
                  color: secondaryGlow.withValues(
                    alpha: scheme.isDark ? 0.08 : 0.04,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AudioFallbackStage extends StatelessWidget {
  const _AudioFallbackStage({
    required this.width,
    required this.height,
    required this.accentColor,
    required this.isDark,
    required this.foreground,
  });

  final double width;
  final double height;
  final Color accentColor;
  final bool isDark;
  final Widget foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('call_audio_backdrop_stage'),
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _AudioBackdropAura(
            width: width,
            height: height,
            accentColor: accentColor,
            isDark: isDark,
          ),
          foreground,
        ],
      ),
    );
  }
}

class _AudioBackdropAura extends StatelessWidget {
  const _AudioBackdropAura({
    required this.width,
    required this.height,
    required this.accentColor,
    required this.isDark,
  });

  final double width;
  final double height;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final outerSize = width * 0.98;
    final middleSize = width * 0.74;
    final innerSize = width * 0.48;
    final ringColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.18);
    final fillColor = Color.lerp(Colors.white, accentColor, 0.22)!;

    return SizedBox(
      key: const Key('call_audio_backdrop_portrait'),
      width: width,
      height: height,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            _AudioBackdropRing(
              size: outerSize,
              fillColor: fillColor.withValues(alpha: isDark ? 0.06 : 0.1),
              borderColor: ringColor,
            ),
            _AudioBackdropRing(
              size: middleSize,
              fillColor: fillColor.withValues(alpha: isDark ? 0.08 : 0.12),
              borderColor: ringColor.withValues(alpha: ringColor.a * 1.1),
            ),
            _AudioBackdropRing(
              size: innerSize,
              fillColor: fillColor.withValues(alpha: isDark ? 0.1 : 0.14),
              borderColor: ringColor.withValues(alpha: ringColor.a * 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioBackdropRing extends StatelessWidget {
  const _AudioBackdropRing({
    required this.size,
    required this.fillColor,
    required this.borderColor,
  });

  final double size;
  final Color fillColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
    );
  }
}

class _BackdropPhotoLayer extends StatelessWidget {
  const _BackdropPhotoLayer({
    required this.contact,
    required this.width,
    required this.height,
    required this.isDark,
  });

  final CallContact contact;
  final double width;
  final double height;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('call_audio_backdrop_portrait'),
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.18),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: isDark ? 16 : 12,
            sigmaY: isDark ? 16 : 12,
          ),
          child: Image.asset(
            contact.photoAssetPath!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _AudioBackdropAura(
              width: width,
              height: height,
              accentColor: contact.accentColor,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallIdentityAvatar extends StatelessWidget {
  const _CallIdentityAvatar({
    required this.contact,
    required this.size,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderWidth = 1,
  });

  final CallContact contact;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? contact.accentColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(
                color: borderColor!,
                width: borderWidth,
              ),
      ),
      child: ClipOval(
        child: CallParticipantAvatar(
          label: contact.avatarLabel,
          size: size,
          avatarUrl: contact.avatarUrl,
          photoAssetPath: contact.photoAssetPath,
          backgroundColor:
              backgroundColor ?? contact.accentColor.withValues(alpha: 0.18),
          foregroundColor: foregroundColor,
        ),
      ),
    );
  }
}

class _AudioAvatarStage extends StatelessWidget {
  const _AudioAvatarStage({
    required this.session,
    required this.compact,
    required this.scheme,
  });

  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 86.0 : 94.0;

    return SizedBox(
      key: const Key('call_audio_avatar_stage'),
      width: avatarSize,
      height: avatarSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: scheme.avatarShadowColor,
              blurRadius: compact ? 22 : 28,
              spreadRadius: scheme.isDark ? 0 : 0.5,
            ),
          ],
        ),
        child: _CallIdentityAvatar(
          contact: session.contact,
          size: avatarSize,
          backgroundColor: scheme.identitySurfaceColor,
          foregroundColor: scheme.primaryText,
          borderColor: scheme.avatarMiddleColor,
          borderWidth: 1.2,
        ),
      ),
    );
  }
}

class _CallControlDockMetrics {
  const _CallControlDockMetrics({required this.compact});

  final bool compact;

  double get controlSize => compact ? 50.0 : 56.0;
  double get buttonGap => compact ? 8.0 : 10.0;
  double get endGap => compact ? 12.0 : 14.0;
  double get panelPaddingH => compact ? 12.0 : 16.0;
  double get panelPaddingV => compact ? 14.0 : 16.0;
  double get rowGap => compact ? 10.0 : 12.0;
  double get borderRadius => compact ? 28.0 : 32.0;

  Color dividerColor(_CallVisualScheme scheme) {
    return scheme.isDark
        ? Colors.white.withValues(alpha: 0.22)
        : scheme.primaryText.withValues(alpha: 0.18);
  }

  Widget frostedShell({
    required _CallVisualScheme scheme,
    Key? panelKey,
    required Widget child,
  }) {
    return _FrostedPanel(
      panelKey: panelKey,
      borderRadius: BorderRadius.circular(borderRadius),
      backgroundColor: scheme.panelBackground,
      borderColor: scheme.panelBorder,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: panelPaddingH,
          vertical: panelPaddingV,
        ),
        child: child,
      ),
    );
  }
}

class _VideoControlDock extends StatelessWidget {
  const _VideoControlDock({
    required this.controller,
    required this.session,
    required this.compact,
    required this.scheme,
  });

  final CallsController controller;
  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final metrics = _CallControlDockMetrics(compact: compact);
    final controlSize = metrics.controlSize;
    final mutedStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.muted,
      active: session.isMuted,
    );
    final speakerStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.speaker,
      active: session.isSpeakerOn,
    );
    final cameraStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.camera,
      active: session.isLocalVideoEnabled,
    );
    final switchStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.camera,
      active: false,
    );
    final buttonGap = metrics.buttonGap;

    Widget actionButton({
      required Key? buttonKey,
      required IconData icon,
      required String label,
      required bool isSelected,
      required _CallControlStyle style,
      required VoidCallback onPressed,
    }) {
      return _CallActionButton(
        buttonKey: buttonKey,
        icon: icon,
        label: label,
        isSelected: isSelected,
        size: controlSize,
        showLabel: false,
        backgroundColor: style.backgroundColor,
        foregroundColor: style.foregroundColor,
        labelColor: style.labelColor,
        borderColor: style.borderColor,
        shadowColor: style.shadowColor,
        onPressed: onPressed,
      );
    }

    final primaryControls = <Widget>[
      actionButton(
        buttonKey: const Key('call_mute_button'),
        icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: session.isMuted ? 'Muted' : 'Mute',
        isSelected: session.isMuted,
        style: mutedStyle,
        onPressed: controller.toggleMute,
      ),
      actionButton(
        buttonKey: const Key('call_audio_route_button'),
        icon: Icons.volume_up_rounded,
        label: 'Speaker',
        isSelected: session.isSpeakerOn,
        style: speakerStyle,
        onPressed: controller.toggleSpeaker,
      ),
      actionButton(
        buttonKey: const Key('call_video_toggle_button'),
        icon: session.isLocalVideoEnabled
            ? Icons.videocam_rounded
            : Icons.videocam_off_rounded,
        label: session.isLocalVideoEnabled ? 'Camera' : 'Cam off',
        isSelected: session.isLocalVideoEnabled,
        style: cameraStyle,
        onPressed: controller.toggleLocalVideo,
      ),
      actionButton(
        buttonKey: const Key('call_switch_camera_button'),
        icon: Icons.flip_camera_ios_rounded,
        label: 'Flip',
        isSelected: false,
        style: switchStyle,
        onPressed: controller.switchCamera,
      ),
    ];

    final endCallButton = _EndCallButton(
      buttonKey: const Key('call_end_button'),
      size: controlSize,
      onPressed: controller.endCurrentCall,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final endGap = metrics.endGap;
        final dividerColor = metrics.dividerColor(scheme);

        final primaryRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < primaryControls.length; index++) ...[
              if (index > 0) SizedBox(width: buttonGap),
              primaryControls[index],
            ],
          ],
        );

        final singleRowWidth = metrics.panelPaddingH * 2 +
            controlSize * 5 +
            buttonGap * 3 +
            endGap * 2 +
            1;
        final fitsSingleRow = constraints.maxWidth >= singleRowWidth;

        Widget dockPill({required Widget child}) {
          return metrics.frostedShell(
            scheme: scheme,
            child: child,
          );
        }

        if (fitsSingleRow) {
          return KeyedSubtree(
            key: const Key('call_video_control_dock'),
            child: dockPill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  primaryRow,
                  SizedBox(width: endGap),
                  _CallDockDivider(
                    height: controlSize,
                    color: dividerColor,
                  ),
                  SizedBox(width: endGap),
                  endCallButton,
                ],
              ),
            ),
          );
        }

        // Two-row cutout: separate pills for primary controls and end call
        // so video stays visible under the sides of the bottom button.
        return Column(
          key: const Key('call_video_control_dock'),
          mainAxisSize: MainAxisSize.min,
          children: [
            dockPill(child: primaryRow),
            SizedBox(height: metrics.rowGap),
            dockPill(child: endCallButton),
          ],
        );
      },
    );
  }
}

class _CallDockDivider extends StatelessWidget {
  const _CallDockDivider({
    required this.height,
    required this.color,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AudioCallActions extends StatelessWidget {
  const _AudioCallActions({
    required this.controller,
    required this.session,
    required this.compact,
    required this.scheme,
  });

  final CallsController controller;
  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final metrics = _CallControlDockMetrics(compact: compact);
    final controlSize = metrics.controlSize;
    final mutedStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.muted,
      active: session.isMuted,
    );
    final speakerStyle = _resolveCallControlStyle(
      scheme: scheme,
      tone: _CallControlTone.speaker,
      active: session.isSpeakerOn,
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: metrics.frostedShell(
        panelKey: const Key('call_audio_control_dock'),
        scheme: scheme,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CallActionButton(
              buttonKey: const Key('call_mute_button'),
              icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: session.isMuted ? 'Muted' : 'Mute',
              isSelected: session.isMuted,
              size: controlSize,
              showLabel: false,
              backgroundColor: mutedStyle.backgroundColor,
              foregroundColor: mutedStyle.foregroundColor,
              labelColor: mutedStyle.labelColor,
              borderColor: mutedStyle.borderColor,
              shadowColor: mutedStyle.shadowColor,
              onPressed: controller.toggleMute,
            ),
            SizedBox(width: metrics.buttonGap),
            _CallActionButton(
              buttonKey: const Key('call_audio_route_button'),
              icon: Icons.volume_up_rounded,
              label: 'Speaker',
              isSelected: session.isSpeakerOn,
              size: controlSize,
              showLabel: false,
              backgroundColor: speakerStyle.backgroundColor,
              foregroundColor: speakerStyle.foregroundColor,
              labelColor: speakerStyle.labelColor,
              borderColor: speakerStyle.borderColor,
              shadowColor: speakerStyle.shadowColor,
              onPressed: controller.toggleSpeaker,
            ),
            SizedBox(width: metrics.endGap),
            _CallDockDivider(
              height: controlSize,
              color: metrics.dividerColor(scheme),
            ),
            SizedBox(width: metrics.endGap),
            _EndCallButton(
              buttonKey: const Key('call_end_button'),
              size: controlSize,
              onPressed: controller.endCurrentCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallActions extends StatelessWidget {
  const _IncomingCallActions({
    required this.controller,
    required this.session,
    required this.textColor,
  });

  final CallsController controller;
  final CallSession session;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallActionButton(
          buttonKey: const Key('call_decline_button'),
          icon: Icons.call_end_rounded,
          label: 'Decline',
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
          size: 84,
          labelColor: textColor,
          onPressed: controller.declineIncomingCall,
        ),
        const SizedBox(width: 36),
        _CallActionButton(
          buttonKey: const Key('call_answer_button'),
          icon: session.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          label: session.isVideo ? 'Answer video' : 'Answer',
          // Theme-routed (colorScheme.primary), not a hardcoded
          // AppPalette.green literal -- matches the decline button's own
          // colorScheme.error usage instead of bypassing the theme, and
          // still resolves to this app's green brand color either way
          // (see AppTheme, which seeds colorScheme.primary from
          // AppPalette.emerald/green).
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          size: 84,
          labelColor: textColor,
          onPressed: () async {
            final didAnswer = await controller.acceptIncomingCall();
            if (didAnswer) {
              return;
            }

            if (context.mounted) {
              _showControllerErrorSnackBar(context, controller);
            }
          },
        ),
      ],
    );
  }
}

class _FrostedPanel extends StatelessWidget {
  const _FrostedPanel({
    required this.child,
    required this.borderRadius,
    this.panelKey,
    this.backgroundColor = const Color(0x1FFFFFFF),
    this.borderColor = const Color(0x2AFFFFFF),
  });

  final Key? panelKey;
  final Widget child;
  final BorderRadius borderRadius;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      key: panelKey,
      borderRadius: borderRadius,
      blurSigma: 18,
      color: backgroundColor,
      borderColor: borderColor,
      showShadow: false,
      child: child,
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.backgroundColor,
    this.foregroundColor,
    this.labelColor,
    this.borderColor,
    this.shadowColor,
    this.isSelected = false,
    this.size = 68,
    this.showLabel = true,
  });

  final Key? buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? labelColor;
  final Color? borderColor;
  final Color? shadowColor;
  final bool isSelected;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    final resolvedBackgroundColor = backgroundColor ??
        (isSelected
            ? Colors.white.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.16));
    final resolvedForegroundColor = foregroundColor ?? Colors.white;
    final resolvedLabelColor = labelColor ?? Colors.white;
    final resolvedBorderColor =
        borderColor ?? Colors.white.withValues(alpha: isSelected ? 0.26 : 0.12);
    final resolvedShadowColor = shadowColor ??
        (isSelected
            ? resolvedBackgroundColor.withValues(alpha: 0.24)
            : Colors.black.withValues(alpha: 0.08));

    final circleButton = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolvedBackgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: resolvedBorderColor,
          width: isSelected ? 1.15 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: resolvedShadowColor,
            blurRadius: isSelected ? (isLightTheme ? 24 : 16) : 10,
            spreadRadius: isSelected ? (isLightTheme ? 0.6 : 0.4) : 0,
            offset: Offset(0, isSelected ? (isLightTheme ? 8 : 4) : 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: resolvedForegroundColor,
              size: size * 0.42,
            ),
          ),
        ),
      ),
    );

    if (!showLabel) {
      return SizedBox.square(
        dimension: size,
        child: circleButton,
      );
    }

    return SizedBox(
      width: size + 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circleButton,
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: resolvedLabelColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({
    required this.onPressed,
    this.buttonKey,
    this.size = 96,
  });

  final Key? buttonKey;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFF3347),
      shape: const CircleBorder(),
      child: InkWell(
        key: buttonKey,
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.call_end_rounded,
            color: Colors.white,
            size: size * 0.4,
          ),
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: color.a * 0.45),
              Colors.transparent,
            ],
            stops: const [0.0, 0.42, 1.0],
          ),
        ),
      ),
    );
  }
}

class _GroupCallVideoGrid extends StatelessWidget {
  const _GroupCallVideoGrid({
    required this.controller,
    required this.session,
    required this.scheme,
  });

  final CallsController controller;
  final CallSession session;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final participants = controller.groupCallParticipants;
    final remoteTracks = controller.remoteVideoTracksByUid;
    final localTrack = session.isReal ? controller.localVideoTrack : null;

    if (participants.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }

    final tiles = participants
        .map(
          (participant) => _GroupCallVideoTile(
            participant: participant,
            track:
                participant.isSelf ? localTrack : remoteTracks[participant.uid],
            scheme: scheme,
          ),
        )
        .toList(growable: false);

    return ColoredBox(
      color: Colors.black,
      child: _groupVideoTileLayout(tiles),
    );
  }

  static const double _gridGap = 1;

  Widget _groupVideoTileLayout(List<_GroupCallVideoTile> tiles) {
    if (tiles.length == 1) {
      return tiles.first;
    }
    if (tiles.length == 2) {
      return Row(
        children: [
          Expanded(child: tiles[0]),
          const SizedBox(width: _gridGap),
          Expanded(child: tiles[1]),
        ],
      );
    }
    if (tiles.length == 3) {
      return Column(
        children: [
          Expanded(child: tiles[0]),
          const SizedBox(height: _gridGap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: tiles[1]),
                const SizedBox(width: _gridGap),
                Expanded(child: tiles[2]),
              ],
            ),
          ),
        ],
      );
    }

    final visible = tiles.take(4).toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: visible[0]),
              const SizedBox(width: _gridGap),
              Expanded(child: visible[1]),
            ],
          ),
        ),
        const SizedBox(height: _gridGap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: visible[2]),
              const SizedBox(width: _gridGap),
              Expanded(child: visible[3]),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupCallVideoTile extends StatelessWidget {
  const _GroupCallVideoTile({
    required this.participant,
    required this.track,
    required this.scheme,
    this.showBorder = true,
  });

  final GroupCallParticipantView participant;
  final lk.VideoTrack? track;
  final _CallVisualScheme scheme;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final accent = _groupVideoTileAccent(participant.state);
    final borderWidth =
        participant.state == GroupCallParticipantState.connected ? 2.4 : 1.2;
    final identityLabel =
        participant.isSelf ? 'You' : _displayCallName(participant.displayName);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: showBorder
            ? Border.all(
                color: accent.withValues(alpha: 0.85),
                width: borderWidth,
              )
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null)
            lk.VideoTrackRenderer(
              track!,
              fit: lk.VideoViewFit.cover,
            )
          else
            ColoredBox(
              color: scheme.isDark
                  ? const Color(0xFF141414)
                  : const Color(0xFF202020),
              child: Center(
                child: _GroupCallVideoIdentity(
                  participant: participant,
                  label: identityLabel,
                  scheme: scheme,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupCallVideoIdentity extends StatelessWidget {
  const _GroupCallVideoIdentity({
    required this.participant,
    required this.label,
    required this.scheme,
  });

  final GroupCallParticipantView participant;
  final String label;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const avatarSize = 88.0;

    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.identitySurfaceColor,
                border: Border.all(
                  color: scheme.avatarMiddleColor.withValues(alpha: 0.9),
                  width: 2.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: ClipOval(
                  child: CallParticipantAvatar(
                    label: participant.avatarLabel,
                    size: avatarSize,
                    avatarUrl: participant.avatarUrl,
                    backgroundColor: scheme.identitySurfaceColor,
                    foregroundColor: scheme.primaryText,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primaryText.withValues(alpha: 0.92),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _groupVideoTileAccent(GroupCallParticipantState state) {
  return switch (state) {
    GroupCallParticipantState.connected => AppPalette.green,
    GroupCallParticipantState.connecting => AppPalette.sky,
    GroupCallParticipantState.ringing => AppPalette.amber,
    GroupCallParticipantState.declined => const Color(0xFFFF5A5F),
    GroupCallParticipantState.unavailable => AppPalette.cloud,
  };
}

String _displayCallName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) {
    return fullName;
  }

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length <= 1) {
    return trimmed;
  }
  return parts.first;
}

String _videoStatusText(CallSession session) {
  return switch (session.phase) {
    CallSessionPhase.incoming =>
      session.contact.isGroup ? 'Incoming group video call' : 'Incoming call',
    CallSessionPhase.ringing =>
      session.isRemoteRinging ? 'Ringing...' : 'Calling...',
    CallSessionPhase.connecting => 'Connecting...',
    CallSessionPhase.connected =>
      'Live • ${_formatDuration(session.elapsedSeconds(DateTime.now()))}',
  };
}

String _audioStatusText(CallSession session) {
  return switch (session.phase) {
    CallSessionPhase.incoming => session.contact.isGroup
        ? 'Incoming group audio call'
        : 'Incoming audio call',
    CallSessionPhase.ringing =>
      session.isRemoteRinging ? 'Ringing...' : 'Calling...',
    CallSessionPhase.connecting => 'Connecting...',
    CallSessionPhase.connected => _formatDuration(
        session.elapsedSeconds(DateTime.now()),
      ),
  };
}

String _remoteVideoStageLabel(CallSession session) {
  final callingVerb = session.isRemoteRinging ? 'Ringing' : 'Calling';
  return switch (session.phase) {
    CallSessionPhase.incoming => session.contact.isGroup
        ? 'Incoming group video call'
        : 'Incoming video call',
    CallSessionPhase.ringing =>
      '$callingVerb ${_displayCallName(session.contact.name)}',
    CallSessionPhase.connecting => 'Preparing video',
    CallSessionPhase.connected => '',
  };
}

_CallVisualScheme _callVisualScheme(
  BuildContext context,
  CallSession session,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = session.contact.accentColor;

  if (isDark) {
    return _CallVisualScheme(
      isDark: true,
      primaryText: Colors.white,
      secondaryText: Colors.white.withValues(alpha: 0.88),
      panelBackground: Colors.white.withValues(alpha: 0.14),
      panelBorder: Colors.white.withValues(alpha: 0.12),
      pillBackground: Colors.black.withValues(alpha: 0.2),
      pillForeground: Colors.white,
      controlBackground: Colors.white.withValues(alpha: 0.12),
      controlSelectedBackground: Colors.white.withValues(alpha: 0.22),
      controlForeground: Colors.white,
      controlLabelColor: Colors.white,
      miniControlBackground: Colors.black.withValues(alpha: 0.24),
      miniControlForeground: Colors.white,
      avatarMiddleColor: Colors.white.withValues(alpha: 0.12),
      avatarShadowColor: accent.withValues(alpha: 0.18),
      identitySurfaceColor: accent.withValues(alpha: 0.18),
    );
  }

  return _CallVisualScheme(
    isDark: false,
    primaryText: AppPalette.ink,
    secondaryText: AppPalette.ink.withValues(alpha: 0.72),
    panelBackground: Colors.white.withValues(alpha: 0.7),
    panelBorder: Colors.white.withValues(alpha: 0.52),
    pillBackground: Colors.white.withValues(alpha: 0.78),
    pillForeground: AppPalette.ink,
    controlBackground: Color.lerp(AppPalette.mist, AppPalette.ink, 0.08)!,
    controlSelectedBackground: Colors.white.withValues(alpha: 0.96),
    controlForeground: AppPalette.ink,
    controlLabelColor: AppPalette.ink,
    miniControlBackground:
        Color.lerp(Colors.white, AppPalette.cloud, 0.16)!.withValues(
      alpha: 0.92,
    ),
    miniControlForeground:
        Color.lerp(AppPalette.slate, AppPalette.ink, 0.12)!.withValues(
      alpha: 0.96,
    ),
    avatarMiddleColor: Colors.white.withValues(alpha: 0.54),
    avatarShadowColor: accent.withValues(alpha: 0.08),
    identitySurfaceColor: Colors.white.withValues(alpha: 0.8),
  );
}

enum _CallControlTone { neutral, muted, speaker, camera, lens }

class _CallControlStyle {
  const _CallControlStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.labelColor,
    required this.borderColor,
    required this.shadowColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Color labelColor;
  final Color borderColor;
  final Color shadowColor;
}

_CallControlStyle _resolveCallControlStyle({
  required _CallVisualScheme scheme,
  required _CallControlTone tone,
  required bool active,
}) {
  final idleStyle = _CallControlStyle(
    backgroundColor: scheme.controlBackground,
    foregroundColor: scheme.controlForeground,
    labelColor: scheme.secondaryText,
    borderColor: scheme.isDark
        ? scheme.panelBorder
        : AppPalette.ink.withValues(alpha: 0.08),
    shadowColor: Colors.black.withValues(alpha: scheme.isDark ? 0.08 : 0.07),
  );

  if (!active && tone != _CallControlTone.lens) {
    return idleStyle;
  }

  final activeBackground = scheme.controlSelectedBackground;
  final activeBorder = scheme.isDark
      ? Colors.white.withValues(alpha: 0.22)
      : AppPalette.ink.withValues(alpha: 0.26);
  final activeShadow =
      Colors.black.withValues(alpha: scheme.isDark ? 0.16 : 0.16);
  final neutralStyle = _CallControlStyle(
    backgroundColor: activeBackground,
    foregroundColor: scheme.controlForeground,
    labelColor: scheme.primaryText,
    borderColor: activeBorder,
    shadowColor: activeShadow,
  );
  final emphasizedSelectedStyle = _CallControlStyle(
    backgroundColor: Colors.white.withValues(alpha: scheme.isDark ? 0.94 : 1),
    foregroundColor: AppPalette.ink.withValues(alpha: 0.96),
    labelColor: scheme.primaryText,
    borderColor: scheme.isDark
        ? Colors.white.withValues(alpha: 0.5)
        : AppPalette.ink.withValues(alpha: 0.3),
    shadowColor: Colors.black.withValues(alpha: scheme.isDark ? 0.24 : 0.2),
  );

  return switch (tone) {
    _CallControlTone.muted => emphasizedSelectedStyle,
    _CallControlTone.speaker => emphasizedSelectedStyle,
    _CallControlTone.camera => emphasizedSelectedStyle,
    _CallControlTone.lens => neutralStyle,
    _CallControlTone.neutral => idleStyle,
  };
}

// Same compact thresholds _VideoCallLayout/_AudioCallLayout already use via
// their own LayoutBuilder constraints -- needed here too now that
// _VideoAmbientStage is hoisted above the safe-area-padded layout that
// used to be the only thing measuring it.
bool _isCompactLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < 390 || size.height < 760;
}

LinearGradient _backgroundGradient(BuildContext context, CallSession session) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (session.isVideo) {
    return LinearGradient(
      colors: isDark
          ? [
              AppPalette.deepOcean,
              Color.lerp(AppPalette.deepOcean, AppPalette.sky, 0.35)!,
              Color.lerp(AppPalette.deepOcean, AppPalette.purple, 0.65)!,
            ]
          : [
              Color.lerp(Colors.white, session.contact.accentColor, 0.16)!,
              Color.lerp(AppPalette.cloud, AppPalette.sky, 0.16)!,
              Color.lerp(AppPalette.mist, AppPalette.purple, 0.12)!,
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  return LinearGradient(
    colors: isDark
        ? [
            Color.lerp(
                AppPalette.deepOcean, session.contact.accentColor, 0.38)!,
            Color.lerp(AppPalette.deepOcean, AppPalette.green, 0.24)!,
            Color.lerp(AppPalette.deepOcean, AppPalette.sky, 0.14)!,
          ]
        : [
            Color.lerp(Colors.white, session.contact.accentColor, 0.2)!,
            Color.lerp(AppPalette.mist, session.contact.accentColor, 0.24)!,
            Color.lerp(AppPalette.cloud, AppPalette.sky, 0.12)!,
          ],
    begin: Alignment.topCenter,
    end: Alignment.bottomRight,
  );
}

class _CallVisualScheme {
  const _CallVisualScheme({
    required this.isDark,
    required this.primaryText,
    required this.secondaryText,
    required this.panelBackground,
    required this.panelBorder,
    required this.pillBackground,
    required this.pillForeground,
    required this.controlBackground,
    required this.controlSelectedBackground,
    required this.controlForeground,
    required this.controlLabelColor,
    required this.miniControlBackground,
    required this.miniControlForeground,
    required this.avatarMiddleColor,
    required this.avatarShadowColor,
    required this.identitySurfaceColor,
  });

  final bool isDark;
  final Color primaryText;
  final Color secondaryText;
  final Color panelBackground;
  final Color panelBorder;
  final Color pillBackground;
  final Color pillForeground;
  final Color controlBackground;
  final Color controlSelectedBackground;
  final Color controlForeground;
  final Color controlLabelColor;
  final Color miniControlBackground;
  final Color miniControlForeground;
  final Color avatarMiddleColor;
  final Color avatarShadowColor;
  final Color identitySurfaceColor;
}

void _showControllerErrorSnackBar(
  BuildContext context,
  CallsController controller,
) {
  final message = controller.errorMessage;
  if (message == null) {
    return;
  }

  showErrorDialog(context, message);
  controller.clearError();
}

String _formatDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
