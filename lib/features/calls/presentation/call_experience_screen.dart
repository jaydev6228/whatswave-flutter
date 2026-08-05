import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../app/theme/app_palette.dart';
import '../application/calls_controller.dart';
import '../domain/call_contact.dart';
import '../domain/call_session.dart';

const Alignment _audioFallbackStageAlignment = Alignment(0, -0.08);

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
      _lastKnownSession = session;
      if (mounted) {
        setState(() {});
      }
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

    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('call_experience_screen'),
        backgroundColor: gradient.colors.first,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: session.isVideo
                  ? _VideoCallLayout(
                      controller: widget.controller,
                      session: session,
                    )
                  : _AudioCallLayout(
                      controller: widget.controller,
                      session: session,
                    ),
            ),
          ),
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
        final textColor = scheme.primaryText;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isCompactHeight ? 10 : 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    key: const Key('call_video_header_block'),
                    padding: EdgeInsets.only(top: isCompactHeight ? 8 : 14),
                    child: Column(
                      key: const Key('call_video_info_column'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CallPill(
                          icon: Icons.videocam_rounded,
                          label: 'Video call',
                          backgroundColor: scheme.pillBackground,
                          foregroundColor: scheme.pillForeground,
                        ),
                        SizedBox(height: isCompactHeight ? 20 : 28),
                        Text(
                          _displayCallName(session.contact.name),
                          key: const Key('call_name_text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.1,
                            fontSize: isCompactWidth ? 48 : 54,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _videoStatusText(session),
                          key: const Key('call_video_status_text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.secondaryText,
                            fontWeight: FontWeight.w700,
                            fontSize: isCompactWidth ? 22 : 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: isCompactWidth ? 12 : 18),
                _LocalVideoPreviewCard(
                  session: session,
                  localVideoTrack:
                      session.isReal ? controller.localVideoTrack : null,
                  width: previewWidth,
                  height: previewHeight,
                  compact: isCompact,
                  scheme: scheme,
                  onSwitchCamera: controller.switchCamera,
                ),
              ],
            ),
            SizedBox(height: isCompactHeight ? 10 : 18),
            Expanded(
              child: _VideoAmbientStage(
                key: const Key('call_video_ambient_stage'),
                controller: controller,
                session: session,
                compact: isCompact,
                scheme: scheme,
              ),
            ),
            SizedBox(height: isCompactHeight ? 14 : 18),
            if (session.phase == CallSessionPhase.incoming)
              _IncomingCallActions(
                controller: controller,
                session: session,
                textColor: textColor,
              )
            else
              Align(
                alignment: Alignment.bottomCenter,
                child: _VideoControlDock(
                  controller: controller,
                  session: session,
                  compact: isCompact,
                  scheme: scheme,
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
        final detailText = session.phase == CallSessionPhase.connected
            ? _formatDuration(session.elapsedSeconds(DateTime.now()))
            : _audioStatusText(session);
        final detailStyle = session.phase == CallSessionPhase.connected
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

        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                SizedBox(height: isCompact ? 24 : 32),
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
                  'Audio call',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.secondaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: isCompact ? 20 : 22,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  detailText,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
                Expanded(
                  child: _AudioCenterStage(
                    session: session,
                    compact: isCompact,
                    scheme: scheme,
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
    final remoteTrack = session.isReal ? controller.remoteVideoTrack : null;
    final showRemoteVideo =
        session.phase == CallSessionPhase.connected && remoteTrack != null;

    return Stack(
      fit: StackFit.expand,
      children: [
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
            color: secondaryGlow.withValues(alpha: scheme.isDark ? 0.18 : 0.1),
          ),
        ),
        Align(
          alignment: const Alignment(0.04, 0.02),
          child: _AmbientGlow(
            size: compact ? 160 : 210,
            color: (scheme.isDark ? Colors.white : AppPalette.cloud).withValues(
              alpha: scheme.isDark ? 0.06 : 0.52,
            ),
          ),
        ),
        if (showRemoteVideo)
          Positioned.fill(
            key: const Key('call_remote_video_surface'),
            child: lk.VideoTrackRenderer(
              remoteTrack,
              fit: lk.VideoViewFit.cover,
            ),
          )
        else if (session.phase != CallSessionPhase.connected)
          Center(
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
                Text(
                  _remoteVideoStageLabel(session),
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
    required this.onSwitchCamera,
    this.localVideoTrack,
  });

  final CallSession session;
  final lk.LocalVideoTrack? localVideoTrack;
  final double width;
  final double height;
  final bool compact;
  final _CallVisualScheme scheme;
  final VoidCallback onSwitchCamera;

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
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                compact ? 10 : 12,
                compact ? 10 : 12,
                compact ? 10 : 12,
              ),
              child: Stack(
                children: [
                  // Video (or its fallback icon) painted first, so the
                  // switch-camera button below always stays on top and
                  // tappable -- Stack children paint in order, and a
                  // full-bleed video here would otherwise cover it.
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
                              key: const Key('call_local_video_disabled_panel'),
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
                  Align(
                    alignment: Alignment.bottomRight,
                    child: _PreviewControlButton(
                      buttonKey: const Key('call_switch_camera_button'),
                      icon: Icons.flip_camera_ios_rounded,
                      size: compact ? 34 : 38,
                      backgroundColor: scheme.miniControlBackground,
                      foregroundColor: scheme.miniControlForeground,
                      borderColor: scheme.isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : scheme.miniControlForeground.withValues(
                              alpha: 0.12,
                            ),
                      shadowColor: Colors.black.withValues(
                        alpha: scheme.isDark ? 0.14 : 0.05,
                      ),
                      onPressed: onSwitchCamera,
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

class _AudioCenterStage extends StatelessWidget {
  const _AudioCenterStage({
    required this.session,
    required this.compact,
    required this.scheme,
  });

  final CallSession session;
  final bool compact;
  final _CallVisualScheme scheme;

  @override
  Widget build(BuildContext context) {
    final hasPhotoBackdrop = session.contact.photoAssetPath != null;

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
              fallbackForeground: hasPhotoBackdrop
                  ? null
                  : _AudioAvatarStage(
                      session: session,
                      compact: compact,
                      scheme: scheme,
                    ),
            ),
          ),
          if (hasPhotoBackdrop)
            Align(
              alignment: _audioFallbackStageAlignment,
              child: _AudioAvatarStage(
                session: session,
                compact: compact,
                scheme: scheme,
              ),
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
    final theme = Theme.of(context);
    final fallback = Center(
      child: Text(
        _displayAvatarLabel(contact.avatarLabel),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: foregroundColor ?? theme.colorScheme.onSurface,
        ),
      ),
    );

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
        child: SizedBox(
          width: size,
          height: size,
          child: contact.photoAssetPath == null
              ? fallback
              : Image.asset(
                  contact.photoAssetPath!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
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
    final controlSize = compact ? 50.0 : 56.0;
    final controlWidth = compact ? 64.0 : 68.0;
    final labelFontSize = compact ? 12.5 : 13.0;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final dockWidth = (compact ? 240.0 : 268.0)
            .clamp(0.0, constraints.maxWidth)
            .toDouble();

        return SizedBox(
          width: dockWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (session.phase != CallSessionPhase.connected) ...[
                _CallPill(
                  icon: Icons.wifi_tethering_rounded,
                  label: session.phase == CallSessionPhase.incoming
                      ? 'Incoming video'
                      : 'Connecting video',
                  backgroundColor: scheme.pillBackground,
                  foregroundColor: scheme.pillForeground,
                ),
                SizedBox(height: compact ? 12 : 14),
              ],
              _FrostedPanel(
                panelKey: const Key('call_video_control_dock'),
                borderRadius: BorderRadius.circular(compact ? 28 : 32),
                backgroundColor: scheme.panelBackground,
                borderColor: scheme.panelBorder,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16,
                    compact ? 14 : 16,
                    compact ? 12 : 16,
                    compact ? 14 : 16,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: compact ? 8 : 10,
                    runSpacing: compact ? 12 : 14,
                    children: [
                      _CallActionButton(
                        buttonKey: const Key('call_mute_button'),
                        icon: session.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: session.isMuted ? 'Muted' : 'Mute',
                        isSelected: session.isMuted,
                        size: controlSize,
                        width: controlWidth,
                        labelFontSize: labelFontSize,
                        backgroundColor: mutedStyle.backgroundColor,
                        foregroundColor: mutedStyle.foregroundColor,
                        labelColor: mutedStyle.labelColor,
                        borderColor: mutedStyle.borderColor,
                        shadowColor: mutedStyle.shadowColor,
                        onPressed: controller.toggleMute,
                      ),
                      _CallActionButton(
                        buttonKey: const Key('call_audio_route_button'),
                        icon: Icons.volume_up_rounded,
                        label: 'Speaker',
                        isSelected: session.isSpeakerOn,
                        size: controlSize,
                        width: controlWidth,
                        labelFontSize: labelFontSize,
                        backgroundColor: speakerStyle.backgroundColor,
                        foregroundColor: speakerStyle.foregroundColor,
                        labelColor: speakerStyle.labelColor,
                        borderColor: speakerStyle.borderColor,
                        shadowColor: speakerStyle.shadowColor,
                        onPressed: controller.toggleSpeaker,
                      ),
                      _CallActionButton(
                        buttonKey: const Key('call_video_toggle_button'),
                        icon: session.isLocalVideoEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        label:
                            session.isLocalVideoEnabled ? 'Camera' : 'Cam off',
                        isSelected: session.isLocalVideoEnabled,
                        size: controlSize,
                        width: controlWidth,
                        labelFontSize: labelFontSize,
                        backgroundColor: cameraStyle.backgroundColor,
                        foregroundColor: cameraStyle.foregroundColor,
                        labelColor: cameraStyle.labelColor,
                        borderColor: cameraStyle.borderColor,
                        shadowColor: cameraStyle.shadowColor,
                        onPressed: controller.toggleLocalVideo,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 14 : 16),
              _EndCallButton(
                buttonKey: const Key('call_end_button'),
                size: compact ? 82 : 88,
                onPressed: controller.endCurrentCall,
              ),
            ],
          ),
        );
      },
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
    final controlSize = compact ? 58.0 : 64.0;
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

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallActionButton(
              buttonKey: const Key('call_mute_button'),
              icon: session.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: session.isMuted ? 'Muted' : 'Mute',
              isSelected: session.isMuted,
              size: controlSize,
              width: compact ? 74 : 80,
              labelFontSize: compact ? 13 : 14,
              backgroundColor: mutedStyle.backgroundColor,
              foregroundColor: mutedStyle.foregroundColor,
              labelColor: mutedStyle.labelColor,
              borderColor: mutedStyle.borderColor,
              shadowColor: mutedStyle.shadowColor,
              onPressed: controller.toggleMute,
            ),
            SizedBox(width: compact ? 22 : 28),
            _CallActionButton(
              buttonKey: const Key('call_audio_route_button'),
              icon: Icons.volume_up_rounded,
              label: 'Speaker',
              isSelected: session.isSpeakerOn,
              size: controlSize,
              width: compact ? 74 : 80,
              labelFontSize: compact ? 13 : 14,
              backgroundColor: speakerStyle.backgroundColor,
              foregroundColor: speakerStyle.foregroundColor,
              labelColor: speakerStyle.labelColor,
              borderColor: speakerStyle.borderColor,
              shadowColor: speakerStyle.shadowColor,
              onPressed: controller.toggleSpeaker,
            ),
          ],
        ),
        SizedBox(height: compact ? 24 : 28),
        _EndCallButton(
          buttonKey: const Key('call_end_button'),
          size: compact ? 84 : 90,
          onPressed: controller.endCurrentCall,
        ),
      ],
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
          backgroundColor: AppPalette.green,
          foregroundColor: Colors.white,
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
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          key: panelKey,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CallPill extends StatelessWidget {
  const _CallPill({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
              ),
            ),
          ],
        ),
      ),
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
    this.width,
    this.labelFontSize = 15,
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
  final double? width;
  final double labelFontSize;

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

    return SizedBox(
      width: width ?? (size + 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
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
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: resolvedLabelColor,
                  fontWeight: FontWeight.w700,
                  fontSize: labelFontSize,
                ),
          ),
        ],
      ),
    );
  }
}

class _PreviewControlButton extends StatelessWidget {
  const _PreviewControlButton({
    required this.icon,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.shadowColor,
    required this.onPressed,
    this.buttonKey,
  });

  final Key? buttonKey;
  final IconData icon;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final Color shadowColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 4),
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
              color: foregroundColor,
              size: size * 0.56,
            ),
          ),
        ),
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
    CallSessionPhase.incoming => 'Incoming call',
    CallSessionPhase.ringing => 'Calling...',
    CallSessionPhase.connecting => 'Connecting...',
    CallSessionPhase.connected =>
      'Live • ${_formatDuration(session.elapsedSeconds(DateTime.now()))}',
  };
}

String _audioStatusText(CallSession session) {
  return switch (session.phase) {
    CallSessionPhase.incoming => 'Incoming audio call',
    CallSessionPhase.ringing => 'Calling...',
    CallSessionPhase.connecting => 'Connecting...',
    CallSessionPhase.connected => _formatDuration(
        session.elapsedSeconds(DateTime.now()),
      ),
  };
}

String _remoteVideoStageLabel(CallSession session) {
  return switch (session.phase) {
    CallSessionPhase.incoming => 'Incoming video call',
    CallSessionPhase.ringing =>
      'Calling ${_displayCallName(session.contact.name)}',
    CallSessionPhase.connecting => 'Preparing video',
    CallSessionPhase.connected => '',
  };
}

String _displayAvatarLabel(String label) {
  final normalized = label.trim().isEmpty ? '?' : label.trim();
  return normalized.length <= 2
      ? normalized.toUpperCase()
      : normalized.substring(0, 2).toUpperCase();
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

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
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
