import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/theme/app_palette.dart';
import '../application/calls_controller.dart';
import '../domain/group_call_participant.dart';
import 'call_participant_avatar.dart';

/// Static profile anchor at the center of the call backdrop — always the viewer.
class GroupCallCenterAnchor extends StatelessWidget {
  const GroupCallCenterAnchor({
    required this.participant,
    required this.size,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
    super.key,
  });

  final GroupCallParticipantView participant;
  final double size;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${participant.displayName}, ${groupCallParticipantStateLabel(participant.state)}',
      child: _PresenceBubbleFace(
        participant: participant,
        size: size,
        primaryText: primaryText,
        surfaceColor: surfaceColor,
        ringColor: ringColor,
        emphasize: true,
        motion: 0,
      ),
    );
  }
}

/// Screensaver-style floating bubbles for everyone except the viewer (audio only).
class GroupCallFloatingField extends StatefulWidget {
  const GroupCallFloatingField({
    required this.participants,
    required this.centerParticipant,
    required this.compact,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
    this.bottomPadding = 0,
    this.topPadding = 0,
    super.key,
  });

  final List<GroupCallParticipantView> participants;
  final GroupCallParticipantView centerParticipant;
  final bool compact;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;
  final double topPadding;
  final double bottomPadding;

  @override
  State<GroupCallFloatingField> createState() => _GroupCallFloatingFieldState();
}

class _GroupCallFloatingFieldState extends State<GroupCallFloatingField>
    with SingleTickerProviderStateMixin {
  final Map<String, _BubbleSim> _simulations = <String, _BubbleSim>{};
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  Size _playfieldSize = Size.zero;
  double _animClock = 0;
  double _physicsAccumulator = 0;
  final math.Random _random = math.Random(7);

  static const double _fixedStep = 1 / 60;

  @override
  void initState() {
    super.initState();
    _syncSimulations();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant GroupCallFloatingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (groupCallParticipantsSignature(widget.participants) ==
            groupCallParticipantsSignature(oldWidget.participants) &&
        widget.centerParticipant.uid == oldWidget.centerParticipant.uid) {
      return;
    }
    _syncSimulations();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _syncSimulations() {
    final activeUids = <String>{};
    for (final participant in widget.participants) {
      if (participant.isSelf ||
          participant.uid == widget.centerParticipant.uid) {
        continue;
      }
      activeUids.add(participant.uid);
      final existing = _simulations[participant.uid];
      if (existing == null) {
        if (participant.state == GroupCallParticipantState.declined ||
            participant.state == GroupCallParticipantState.unavailable) {
          continue;
        }
        final sim = _BubbleSim.spawn(
          participant: participant,
          random: _random,
        );
        if (participant.state == GroupCallParticipantState.connected) {
          sim.beginMerge();
          sim.mergeProgress = 1;
          sim.mode = _BubbleMotionMode.docked;
        }
        _simulations[participant.uid] = sim;
        continue;
      }

      final previousState = existing.participant.state;
      existing.participant = participant;

      if (participant.state == GroupCallParticipantState.declined &&
          previousState != GroupCallParticipantState.declined) {
        existing.beginExplosion();
      } else if (participant.state == GroupCallParticipantState.unavailable &&
          previousState != GroupCallParticipantState.unavailable) {
        existing.beginExplosion();
      } else if (participant.state == GroupCallParticipantState.connected &&
          previousState != GroupCallParticipantState.connected) {
        existing.beginMerge();
      }
    }

    for (final uid in _simulations.keys.toList(growable: false)) {
      if (!activeUids.contains(uid)) {
        final sim = _simulations[uid]!;
        if (!sim.isExploding) {
          sim.beginExplosion();
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _playfieldSize.isEmpty) {
      return;
    }

    final dtSeconds = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    if (dtSeconds <= 0 || dtSeconds > 0.1) {
      return;
    }

    _animClock += dtSeconds;
    _physicsAccumulator += dtSeconds;

    var stepped = false;
    while (_physicsAccumulator >= _fixedStep) {
      _stepPhysics(_fixedStep);
      _physicsAccumulator -= _fixedStep;
      stepped = true;
    }

    if (stepped) {
      setState(() {
        _simulations.removeWhere((_, sim) => sim.isFinished);
      });
    }
  }

  void _stepPhysics(double dt) {
    final width = _playfieldSize.width;
    final height = _playfieldSize.height;
    final center = Offset(width / 2, height / 2);
    final centerRadius = widget.compact ? 56.0 : 64.0;
    final bubbleRadius = widget.compact ? 27.0 : 31.0;
    final bounds = Rect.fromLTWH(
      bubbleRadius + 8,
      widget.topPadding + bubbleRadius + 8,
      width - (bubbleRadius + 8) * 2,
      height -
          widget.topPadding -
          widget.bottomPadding -
          (bubbleRadius + 8) * 2,
    );

    for (final sim in _simulations.values) {
      sim.ensureSpawnedIn(bounds, center, centerRadius, bubbleRadius, _random);
      final dockedPositions = _simulations.values
          .where((entry) => entry.mode == _BubbleMotionMode.docked)
          .map((entry) => entry.position)
          .toList(growable: false);
      switch (sim.mode) {
        case _BubbleMotionMode.free:
          sim.stepFreeMotion(
            dt: dt,
            bounds: bounds,
            center: center,
            centerRadius: centerRadius,
            bubbleRadius: bubbleRadius,
            dockedPositions: dockedPositions,
          );
        case _BubbleMotionMode.merging:
          sim.stepMerge(
            dt: dt,
            center: center,
            centerRadius: centerRadius,
            bubbleRadius: bubbleRadius,
          );
        case _BubbleMotionMode.docked:
          sim.stepDocked(
            center: center,
            centerRadius: centerRadius,
            bubbleRadius: bubbleRadius,
          );
        case _BubbleMotionMode.exploding:
          sim.advance(dt);
        case _BubbleMotionMode.finished:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bubbleRadius = widget.compact ? 27.0 : 31.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_playfieldSize != nextSize) {
          _playfieldSize = nextSize;
        }

        return RepaintBoundary(
          child: Semantics(
            container: true,
            label: 'Group call participants',
            child: Stack(
              key: const Key('call_group_presence_constellation'),
              clipBehavior: Clip.none,
              children: [
                for (final sim in _simulations.values)
                  _AnimatedFloater(
                    sim: sim,
                    bubbleRadius: bubbleRadius,
                    animClock: _animClock,
                    primaryText: widget.primaryText,
                    surfaceColor: widget.surfaceColor,
                    ringColor: widget.ringColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

GroupCallParticipantView _resolveCenterParticipant(
  List<GroupCallParticipantView> participants,
) {
  return participants.firstWhere(
    (entry) => entry.isSelf,
    orElse: () => participants.firstWhere(
      (entry) => entry.isHost,
      orElse: () => participants.first,
    ),
  );
}

GroupCallParticipantView groupCallCenterParticipant(
  List<GroupCallParticipantView> participants,
) {
  return _resolveCenterParticipant(participants);
}

String groupCallParticipantsSignature(
  List<GroupCallParticipantView> participants,
) {
  return participants
      .map(
        (participant) =>
            '${participant.uid}:${participant.state.index}:${participant.isHost}',
      )
      .join('|');
}

/// Keeps bubble physics isolated from unrelated call-screen rebuilds such as
/// the once-per-second duration timer.
class GroupCallFloatingFieldHost extends StatefulWidget {
  const GroupCallFloatingFieldHost({
    required this.controller,
    required this.compact,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
    this.topPadding = 0,
    this.bottomPadding = 0,
    super.key,
  });

  final CallsController controller;
  final bool compact;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;
  final double topPadding;
  final double bottomPadding;

  @override
  State<GroupCallFloatingFieldHost> createState() =>
      _GroupCallFloatingFieldHostState();
}

class _GroupCallFloatingFieldHostState
    extends State<GroupCallFloatingFieldHost> {
  late String _signature;

  @override
  void initState() {
    super.initState();
    _signature = groupCallParticipantsSignature(
      widget.controller.groupCallParticipants,
    );
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GroupCallFloatingFieldHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _handleControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final nextSignature = groupCallParticipantsSignature(
      widget.controller.groupCallParticipants,
    );
    if (nextSignature == _signature) {
      return;
    }
    _signature = nextSignature;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.controller.groupCallParticipants;
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    return GroupCallFloatingField(
      key: const ValueKey('group_call_floating_field'),
      participants: participants,
      centerParticipant: groupCallCenterParticipant(participants),
      compact: widget.compact,
      primaryText: widget.primaryText,
      surfaceColor: widget.surfaceColor,
      ringColor: widget.ringColor,
      topPadding: widget.topPadding,
      bottomPadding: widget.bottomPadding,
    );
  }
}

/// Static center anchor that only rebuilds when the viewer's presence changes.
class GroupCallCenterAnchorHost extends StatefulWidget {
  const GroupCallCenterAnchorHost({
    required this.controller,
    required this.compact,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
    super.key,
  });

  final CallsController controller;
  final bool compact;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;

  @override
  State<GroupCallCenterAnchorHost> createState() =>
      _GroupCallCenterAnchorHostState();
}

class _GroupCallCenterAnchorHostState extends State<GroupCallCenterAnchorHost> {
  late String _signature;

  @override
  void initState() {
    super.initState();
    _signature = _selfSignature(widget.controller.groupCallParticipants);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant GroupCallCenterAnchorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _handleControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  String _selfSignature(List<GroupCallParticipantView> participants) {
    if (participants.isEmpty) {
      return '';
    }
    final self = participants.firstWhere(
      (entry) => entry.isSelf,
      orElse: () => groupCallCenterParticipant(participants),
    );
    return '${self.uid}:${self.state.index}';
  }

  void _handleControllerChanged() {
    final nextSignature =
        _selfSignature(widget.controller.groupCallParticipants);
    if (nextSignature == _signature) {
      return;
    }
    _signature = nextSignature;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.controller.groupCallParticipants;
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final center = groupCallCenterParticipant(participants);
    final size = widget.compact ? 72.0 : 82.0;
    return GroupCallCenterAnchor(
      participant: center,
      size: size,
      primaryText: widget.primaryText,
      surfaceColor: widget.surfaceColor,
      ringColor: widget.ringColor,
    );
  }
}

enum _BubbleMotionMode { free, merging, docked, exploding, finished }

class _BubbleSim {
  _BubbleSim({
    required this.participant,
    required this.position,
    required this.velocity,
    required this.dockAngle,
  });

  factory _BubbleSim.spawn({
    required GroupCallParticipantView participant,
    required math.Random random,
  }) {
    final angle = random.nextDouble() * math.pi * 2;
    final speed = 48 + random.nextDouble() * 28;
    return _BubbleSim(
      participant: participant,
      position: Offset.zero,
      velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
      dockAngle: random.nextDouble() * math.pi * 2,
    );
  }

  GroupCallParticipantView participant;
  Offset position;
  Offset velocity;
  double dockAngle;
  _BubbleMotionMode mode = _BubbleMotionMode.free;
  double mergeProgress = 0;
  double explodeProgress = 0;
  bool _spawned = false;

  bool get isExploding => mode == _BubbleMotionMode.exploding;
  bool get isFinished => mode == _BubbleMotionMode.finished;

  void ensureSpawnedIn(
    Rect bounds,
    Offset center,
    double centerRadius,
    double bubbleRadius,
    math.Random random,
  ) {
    if (_spawned || bounds.width <= 0 || bounds.height <= 0) {
      return;
    }
    _spawned = true;
    for (var attempt = 0; attempt < 24; attempt++) {
      final candidate = Offset(
        bounds.left + random.nextDouble() * bounds.width,
        bounds.top + random.nextDouble() * bounds.height,
      );
      if ((candidate - center).distance > centerRadius + bubbleRadius + 18) {
        position = candidate;
        return;
      }
    }
    position = Offset(bounds.center.dx, bounds.top + bubbleRadius + 12);
  }

  void beginMerge() {
    if (mode == _BubbleMotionMode.exploding) {
      return;
    }
    mode = _BubbleMotionMode.merging;
    mergeProgress = 0;
  }

  void beginExplosion() {
    mode = _BubbleMotionMode.exploding;
    explodeProgress = 0;
  }

  void advance(double dt) {
    if (mode == _BubbleMotionMode.exploding) {
      explodeProgress = (explodeProgress + dt * 1.8).clamp(0.0, 1.0);
      if (explodeProgress >= 1) {
        mode = _BubbleMotionMode.finished;
      }
    }
  }

  void stepFreeMotion({
    required double dt,
    required Rect bounds,
    required Offset center,
    required double centerRadius,
    required double bubbleRadius,
    List<Offset> dockedPositions = const <Offset>[],
  }) {
    position += velocity * dt;

    _bounceWall(
      axis: _Axis.horizontal,
      bounds: bounds,
      bubbleRadius: bubbleRadius,
    );
    _bounceWall(
      axis: _Axis.vertical,
      bounds: bounds,
      bubbleRadius: bubbleRadius,
    );

    _bounceCircle(
      center: center,
      radius: centerRadius + bubbleRadius + 4,
    );
    for (final docked in dockedPositions) {
      if ((docked - position).distance < 1) {
        continue;
      }
      _bounceCircle(
        center: docked,
        radius: bubbleRadius + 4,
      );
    }

    if (participant.state == GroupCallParticipantState.connecting) {
      final toCenter = center - position;
      velocity += toCenter * (dt * 0.45);
    }

    final maxSpeed = 92.0;
    final speed = velocity.distance;
    if (speed > maxSpeed) {
      velocity = velocity / speed * maxSpeed;
    }
  }

  void _bounceCircle({
    required Offset center,
    required double radius,
  }) {
    final delta = position - center;
    final distance = delta.distance;
    if (distance <= 0 || distance >= radius) {
      return;
    }
    final normal = delta / distance;
    position = center + normal * radius;
    final dot = velocity.dx * normal.dx + velocity.dy * normal.dy;
    if (dot < 0) {
      final reflected = velocity - normal * (2 * dot);
      velocity = reflected * 0.9;
    }
  }

  void stepMerge({
    required double dt,
    required Offset center,
    required double centerRadius,
    required double bubbleRadius,
  }) {
    final target = center +
        Offset(
          math.cos(dockAngle) * (centerRadius + bubbleRadius * 0.72),
          math.sin(dockAngle) * (centerRadius + bubbleRadius * 0.72),
        );
    final blend = math.min(1.0, dt * 5.5);
    position += (target - position) * blend;
    velocity = Offset.zero;
    mergeProgress = math.min(1.0, mergeProgress + dt * 1.35);
    if ((target - position).distance < 0.8) {
      position = target;
      mode = _BubbleMotionMode.docked;
      mergeProgress = 1;
    }
  }

  void stepDocked({
    required Offset center,
    required double centerRadius,
    required double bubbleRadius,
  }) {
    position = center +
        Offset(
          math.cos(dockAngle) * (centerRadius + bubbleRadius * 0.72),
          math.sin(dockAngle) * (centerRadius + bubbleRadius * 0.72),
        );
    velocity = Offset.zero;
  }

  void _bounceWall({
    required _Axis axis,
    required Rect bounds,
    required double bubbleRadius,
  }) {
    if (axis == _Axis.horizontal) {
      if (position.dx - bubbleRadius < bounds.left) {
        position = Offset(bounds.left + bubbleRadius, position.dy);
        velocity = Offset(velocity.dx.abs() * 0.92, velocity.dy);
      } else if (position.dx + bubbleRadius > bounds.right) {
        position = Offset(bounds.right - bubbleRadius, position.dy);
        velocity = Offset(-velocity.dx.abs() * 0.92, velocity.dy);
      }
      return;
    }

    if (position.dy - bubbleRadius < bounds.top) {
      position = Offset(position.dx, bounds.top + bubbleRadius);
      velocity = Offset(velocity.dx, velocity.dy.abs() * 0.92);
    } else if (position.dy + bubbleRadius > bounds.bottom) {
      position = Offset(position.dx, bounds.bottom - bubbleRadius);
      velocity = Offset(velocity.dx, -velocity.dy.abs() * 0.92);
    }
  }
}

enum _Axis { horizontal, vertical }

class _AnimatedFloater extends StatelessWidget {
  const _AnimatedFloater({
    required this.sim,
    required this.bubbleRadius,
    required this.animClock,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
  });

  final _BubbleSim sim;
  final double bubbleRadius;
  final double animClock;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final size = bubbleRadius * 2;
    final motion = (animClock * 0.22) % 1.0;

    if (sim.mode == _BubbleMotionMode.exploding) {
      final t = Curves.easeIn.transform(sim.explodeProgress);
      final scale = 1 + math.sin(t * math.pi) * 0.35;
      return Positioned(
        left: sim.position.dx - size / 2,
        top: sim.position.dy - size / 2,
        child: Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: _ExplosionBurst(
              size: size,
              progress: t,
              accent: _accentFor(sim.participant.state, ringColor),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: sim.position.dx - size / 2,
      top: sim.position.dy - size / 2,
      child: _PresenceBubbleFace(
        participant: sim.participant,
        size: size,
        primaryText: primaryText,
        surfaceColor: surfaceColor,
        ringColor: ringColor,
        motion: motion,
        emphasize: sim.mode == _BubbleMotionMode.docked,
      ),
    );
  }
}

class _ExplosionBurst extends StatelessWidget {
  const _ExplosionBurst({
    required this.size,
    required this.progress,
    required this.accent,
  });

  final double size;
  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Transform.rotate(
              angle: i * math.pi / 3,
              child: Container(
                width: size * (0.35 + progress * 0.8),
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: accent.withValues(alpha: (1 - progress) * 0.8),
                ),
              ),
            ),
          Container(
            width: size * (1 - progress * 0.65),
            height: size * (1 - progress * 0.65),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: (1 - progress) * 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceBubbleFace extends StatelessWidget {
  const _PresenceBubbleFace({
    required this.participant,
    required this.size,
    required this.primaryText,
    required this.surfaceColor,
    required this.ringColor,
    required this.motion,
    this.emphasize = false,
  });

  final GroupCallParticipantView participant;
  final double size;
  final Color primaryText;
  final Color surfaceColor;
  final Color ringColor;
  final double motion;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final state = participant.state;
    final accent = _accentFor(state, ringColor);
    final ringWidth = emphasize ? 3.2 : 2.4;
    final glowStrength = emphasize ? 0.34 : 0.22;

    return Semantics(
      label:
          '${participant.displayName}, ${groupCallParticipantStateLabel(state)}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (state == GroupCallParticipantState.ringing)
              ..._ringingRipples(size, accent, motion),
            if (state == GroupCallParticipantState.connected)
              _steadyGlow(size, accent, glowStrength),
            if (state == GroupCallParticipantState.connecting)
              _connectingHalo(size, accent, motion),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surfaceColor,
                border: Border.all(
                  color: accent.withValues(alpha: 0.95),
                  width: ringWidth,
                ),
                boxShadow: state == GroupCallParticipantState.connected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: glowStrength),
                          blurRadius: size * 0.22,
                          spreadRadius: size * 0.02,
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: CallParticipantAvatar(
                  label: participant.avatarLabel,
                  size: size,
                  avatarUrl: participant.avatarUrl,
                  backgroundColor: surfaceColor,
                  foregroundColor: primaryText,
                ),
              ),
            ),
            if (participant.isHost)
              Positioned(
                top: -2,
                left: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.amber,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: surfaceColor,
                      width: 1.2,
                    ),
                  ),
                  child: const SizedBox(
                    width: 14,
                    height: 14,
                    child: Icon(
                      Icons.star_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _ringingRipples(double size, Color accent, double motion) {
    return List<Widget>.generate(2, (index) {
      final progress = (motion + index * 0.5) % 1.0;
      final diameter = size + progress * size * 0.85;
      return Positioned(
        width: diameter,
        height: diameter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: (1 - progress) * 0.55),
              width: 1.6,
            ),
          ),
        ),
      );
    });
  }

  Widget _steadyGlow(double size, Color accent, double strength) {
    return IgnorePointer(
      child: Container(
        width: size * 1.35,
        height: size * 1.35,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              accent.withValues(alpha: strength),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectingHalo(double size, Color accent, double motion) {
    return Transform.rotate(
      angle: motion * math.pi * 2,
      child: Container(
        width: size * 1.18,
        height: size * 1.18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accent.withValues(alpha: 0.55),
            width: 1.8,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
      ),
    );
  }
}

Color _accentFor(GroupCallParticipantState state, Color ringColor) {
  return switch (state) {
    GroupCallParticipantState.connected => AppPalette.green,
    GroupCallParticipantState.connecting => AppPalette.sky,
    GroupCallParticipantState.ringing => AppPalette.amber,
    GroupCallParticipantState.declined => const Color(0xFFFF5A5F),
    GroupCallParticipantState.unavailable => ringColor,
  };
}
