import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/backend_runtime_config.dart';
import '../../../core/config/runtime_flags.dart';
import '../../../core/integrations/backend_repository_bundle.dart';
import '../../../core/integrations/integration_hub_controller.dart';
import '../../calls/presentation/call_signaling_test_screen.dart';
import '../../calls/presentation/livekit_test_screen.dart';
import '../../shared/widgets/empty_state_card.dart';
import '../../shared/widgets/error_dialog.dart';
import '../../shared/widgets/section_heading.dart';

class BackendSyncScreen extends StatefulWidget {
  const BackendSyncScreen({
    required this.controller,
    super.key,
  });

  final IntegrationHubController controller;

  @override
  State<BackendSyncScreen> createState() => _BackendSyncScreenState();
}

class _BackendSyncScreenState extends State<BackendSyncScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.ensureLoaded();
  }

  Future<void> _copyIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await showErrorDialog(context, 'Not signed in.');
      return;
    }

    final token = await user.getIdToken();
    if (!mounted) {
      return;
    }
    if (token == null) {
      await showErrorDialog(context, 'Could not fetch an ID token.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.controller.hasLoaded && widget.controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          key: const Key('backend_sync_screen'),
          appBar: AppBar(
            title: const Text('Backend and sync'),
            actions: [
              IconButton(
                key: const Key('backend_sync_sync_now_button'),
                tooltip: 'Sync push registration',
                onPressed: widget.controller.isSyncingPush
                    ? null
                    : widget.controller.syncPushRegistration,
                icon: widget.controller.isSyncingPush
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vendor-neutral integration seams for push, sync, uploads, and future Firebase or AWS delivery.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        if (widget.controller.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          MaterialBanner(
                            key: const Key('backend_sync_error_banner'),
                            content: Text(widget.controller.errorMessage!),
                            actions: [
                              TextButton(
                                onPressed: widget.controller.clearError,
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Runtime configuration'),
                        const SizedBox(height: 12),
                        Card(
                          key: const Key('backend_sync_runtime_config_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoLine(
                                  label: 'Backend mode',
                                  value: widget.controller.runtimeConfig
                                      .backendMode.label,
                                ),
                                _InfoLine(
                                  label: 'Environment',
                                  value: widget.controller.runtimeConfig
                                      .environment.label,
                                ),
                                _InfoLine(
                                  label: 'Call provider',
                                  value: widget.controller.runtimeConfig
                                      .callingProvider.label,
                                ),
                                _InfoLine(
                                  label: 'Firebase project',
                                  value: widget.controller.runtimeConfig
                                      .firebaseProjectLabel,
                                ),
                                _InfoLine(
                                  label: 'Firebase emulators',
                                  value: widget.controller.runtimeConfig
                                          .useFirebaseEmulators
                                      ? 'Enabled'
                                      : 'Disabled',
                                ),
                                _InfoLine(
                                  label: 'Crash reporting',
                                  value: widget.controller.runtimeConfig
                                          .crashReportingEnabled
                                      ? 'Enabled'
                                      : 'Disabled',
                                ),
                                _InfoLine(
                                  label: 'Analytics',
                                  value: widget.controller.runtimeConfig
                                          .analyticsEnabled
                                      ? 'Enabled'
                                      : 'Disabled',
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (kEnableDemoSurfaces) ...[
                          const SizedBox(height: 24),
                          const SectionHeading(title: 'Debug tools'),
                          const SizedBox(height: 12),
                          Card(
                            key: const Key('backend_sync_debug_tools_card'),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'QA-only actions, compiled out of release builds.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    key: const Key(
                                        'backend_sync_test_crash_button'),
                                    onPressed: () =>
                                        FirebaseCrashlytics.instance.crash(),
                                    icon: const Icon(Icons.bug_report_outlined),
                                    label: const Text('Send test crash'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    key: const Key(
                                        'backend_sync_livekit_test_button'),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const LiveKitTestScreen(),
                                      ),
                                    ),
                                    icon: const Icon(Icons.videocam_outlined),
                                    label:
                                        const Text('Test LiveKit connection'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    key: const Key(
                                        'backend_sync_copy_id_token_button'),
                                    onPressed: _copyIdToken,
                                    icon: const Icon(Icons.key_outlined),
                                    label: const Text('Copy Firebase ID token'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    key: const Key(
                                        'backend_sync_call_signaling_test_button'),
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const CallSignalingTestScreen(),
                                      ),
                                    ),
                                    icon: const Icon(Icons.call_outlined),
                                    label: const Text('Test call signaling'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Firebase setup status'),
                        const SizedBox(height: 12),
                        Card(
                          key:
                              const Key('backend_sync_firebase_checklist_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: widget
                                  .controller.runtimeConfig.firebaseChecklist
                                  .map((item) {
                                return _ChecklistTile(item: item);
                              }).toList(growable: false),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Release blockers'),
                        const SizedBox(height: 12),
                        Card(
                          key: const Key('backend_sync_release_checklist_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: widget
                                  .controller.runtimeConfig.releaseChecklist
                                  .map((item) {
                                return _ChecklistTile(item: item);
                              }).toList(growable: false),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Delivery targets'),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.controller.deliveryTargets
                                      .map((target) {
                                    final isActive = target ==
                                            widget.controller
                                                .activePushDeliveryTarget ||
                                        target ==
                                            widget.controller
                                                .activeMediaDeliveryTarget;
                                    return DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? theme.colorScheme.primary
                                                .withValues(alpha: 0.14)
                                            : theme.colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          target.label,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            color: isActive
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(growable: false),
                                ),
                                const SizedBox(height: 14),
                                ...widget.controller.deliveryTargets
                                    .map((target) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          target ==
                                                      widget.controller
                                                          .activePushDeliveryTarget ||
                                                  target ==
                                                      widget.controller
                                                          .activeMediaDeliveryTarget
                                              ? Icons
                                                  .check_circle_outline_rounded
                                              : Icons.arrow_forward_ios_rounded,
                                          size: 18,
                                          color: target ==
                                                      widget.controller
                                                          .activePushDeliveryTarget ||
                                                  target ==
                                                      widget.controller
                                                          .activeMediaDeliveryTarget
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.45),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                target.label,
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                target.description,
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Provider readiness'),
                        const SizedBox(height: 12),
                        Card(
                          key:
                              const Key('backend_sync_provider_readiness_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                for (var index = 0;
                                    index <
                                        widget.controller.providerReadiness
                                            .length;
                                    index++) ...[
                                  _ProviderReadinessTile(
                                    provider: widget
                                        .controller.providerReadiness[index],
                                    isActive: widget
                                                .controller
                                                .providerReadiness[index]
                                                .target ==
                                            widget.controller
                                                .activePushDeliveryTarget ||
                                        widget
                                                .controller
                                                .providerReadiness[index]
                                                .target ==
                                            widget.controller
                                                .activeMediaDeliveryTarget,
                                  ),
                                  if (index <
                                      widget.controller.providerReadiness
                                              .length -
                                          1)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Divider(height: 1),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Repository adapters'),
                        const SizedBox(height: 12),
                        Card(
                          key: const Key('backend_sync_repository_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                for (var index = 0;
                                    index <
                                        widget.controller.repositoryReadiness
                                            .length;
                                    index++) ...[
                                  _RepositoryAdapterTile(
                                    adapter: widget
                                        .controller.repositoryReadiness[index],
                                  ),
                                  if (index <
                                      widget.controller.repositoryReadiness
                                              .length -
                                          1)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Divider(height: 1),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Push registration'),
                        const SizedBox(height: 12),
                        Card(
                          key: const Key('backend_sync_push_card'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.controller.pushRegistration.state
                                            .label,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    _StatePill(
                                      label: widget.controller.pushRegistration
                                          .state.label,
                                      color: _pillColorForPushState(
                                        theme,
                                        widget
                                            .controller.pushRegistration.state,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.controller.pushRegistration.state
                                      .description,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 14),
                                _InfoLine(
                                  label: 'Signed in',
                                  value: widget.controller.isAuthenticated
                                      ? 'Yes'
                                      : 'No',
                                ),
                                _InfoLine(
                                  label: 'Adapter',
                                  value: widget.controller.pushProviderName,
                                ),
                                _InfoLine(
                                  label: 'Notifications enabled',
                                  value: widget.controller.notificationsEnabled
                                      ? 'Yes'
                                      : 'No',
                                ),
                                _InfoLine(
                                  label: 'Token preview',
                                  value: widget.controller.pushRegistration
                                          .tokenPreview ??
                                      'Not synced yet',
                                ),
                                _InfoLine(
                                  label: 'Last sync',
                                  value: _formatDateTime(
                                    widget.controller.pushRegistration
                                        .lastSyncedAt,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionHeading(title: 'Recent sync activity'),
                        const SizedBox(height: 12),
                        if (widget.controller.recentActivity.isEmpty)
                          const EmptyStateCard(
                            icon: Icons.sync_problem_rounded,
                            title: 'No sync activity yet',
                            message:
                                'As auth, chat, status, calls, and community actions move through repository seams, they will appear here.',
                          )
                        else
                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 10, 18, 10),
                              child: Column(
                                children: widget.controller.recentActivity
                                    .map((entry) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _StateDot(
                                          color: entry.status ==
                                                  SyncActivityStatus.synced
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.title,
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${entry.source} • ${entry.status.label} • ${_formatDateTime(entry.createdAt)}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: 0.68),
                                                ),
                                              ),
                                              if (entry.details != null &&
                                                  entry
                                                      .details!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(entry.details!),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(growable: false),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(
                              child: SectionHeading(title: 'Media pipeline'),
                            ),
                            if (widget.controller.failedTransferCount > 0)
                              TextButton(
                                key: const Key(
                                    'backend_sync_retry_uploads_button'),
                                onPressed: widget
                                        .controller.isRetryingFailedTransfers
                                    ? null
                                    : widget.controller.retryFailedTransfers,
                                child: Text(
                                  widget.controller.isRetryingFailedTransfers
                                      ? 'Retrying...'
                                      : 'Retry failed',
                                ),
                              ),
                            TextButton(
                              key: const Key(
                                  'backend_sync_clear_uploads_button'),
                              onPressed: widget
                                      .controller.isClearingCompletedTransfers
                                  ? null
                                  : widget.controller.clearCompletedTransfers,
                              child: Text(
                                widget.controller.isClearingCompletedTransfers
                                    ? 'Clearing...'
                                    : 'Clear uploaded',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Active upload adapter: ${widget.controller.mediaTransferProviderName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.controller.mediaTransfers.isEmpty)
                          const EmptyStateCard(
                            icon: Icons.perm_media_outlined,
                            title: 'No media transfers yet',
                            message:
                                'Photo, video, file, and status uploads will be tracked here before real cloud storage is wired in.',
                          )
                        else
                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 10, 18, 10),
                              child: Column(
                                children:
                                    widget.controller.mediaTransfers.map((job) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _iconForTransferKind(job.kind),
                                          color: _pillColorForTransferState(
                                            theme,
                                            job.state,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                job.label,
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${job.source} • ${job.kind.label} • ${_formatDateTime(job.createdAt)}',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withValues(alpha: 0.68),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _StatePill(
                                          label: job.state.label,
                                          color: _pillColorForTransferState(
                                            theme,
                                            job.state,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(growable: false),
                              ),
                            ),
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

class _ProviderReadinessTile extends StatelessWidget {
  const _ProviderReadinessTile({
    required this.provider,
    required this.isActive,
  });

  final IntegrationProviderReadiness provider;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _colorForProviderStatus(
      theme,
      provider.status,
      isActive: isActive,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.target.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.providerName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            _StatePill(
              label: isActive ? 'Live now' : provider.status.label,
              color: accentColor,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(provider.summary, style: theme.textTheme.bodyMedium),
        if (provider.capabilities.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: provider.capabilities.map((capability) {
              return _CapabilityChip(
                label: capability,
                color: accentColor,
              );
            }).toList(growable: false),
          ),
        ],
        if (provider.nextSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Next setup',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final step in provider.nextSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _RepositoryAdapterTile extends StatelessWidget {
  const _RepositoryAdapterTile({required this.adapter});

  final RepositoryAdapterReadiness adapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _colorForRepositoryStatus(theme, adapter.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    adapter.featureArea,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    adapter.providerName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            _StatePill(
              label: adapter.status.label,
              color: accentColor,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(adapter.summary, style: theme.textTheme.bodyMedium),
        if (adapter.capabilities.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: adapter.capabilities.map((capability) {
              return _CapabilityChip(
                label: capability,
                color: accentColor,
              );
            }).toList(growable: false),
          ),
        ],
        if (adapter.nextSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Next setup',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final step in adapter.nextSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({required this.item});

  final BackendChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = item.isComplete
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isComplete
                ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            color: accentColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatePill(
            label: item.isComplete ? 'Ready' : 'Pending',
            color: accentColor,
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

Color _pillColorForPushState(ThemeData theme, PushRegistrationState state) {
  return switch (state) {
    PushRegistrationState.registered => theme.colorScheme.primary,
    PushRegistrationState.paused => theme.colorScheme.secondary,
    PushRegistrationState.actionRequired =>
      theme.colorScheme.onSurface.withValues(alpha: 0.7),
    PushRegistrationState.failed => theme.colorScheme.error,
  };
}

Color _colorForProviderStatus(
  ThemeData theme,
  IntegrationProviderStatus status, {
  required bool isActive,
}) {
  if (isActive) {
    return theme.colorScheme.primary;
  }

  return switch (status) {
    IntegrationProviderStatus.active => theme.colorScheme.primary,
    IntegrationProviderStatus.scaffolded => theme.colorScheme.secondary,
    IntegrationProviderStatus.compatible =>
      theme.colorScheme.onSurface.withValues(alpha: 0.72),
  };
}

Color _colorForRepositoryStatus(
  ThemeData theme,
  RepositoryAdapterStatus status,
) {
  return switch (status) {
    RepositoryAdapterStatus.localActive => theme.colorScheme.primary,
    RepositoryAdapterStatus.localFallback => theme.colorScheme.secondary,
    RepositoryAdapterStatus.liveCloud => theme.colorScheme.primary,
  };
}

Color _pillColorForTransferState(ThemeData theme, MediaTransferState state) {
  return switch (state) {
    MediaTransferState.queued => theme.colorScheme.secondary,
    MediaTransferState.uploading => theme.colorScheme.primary,
    MediaTransferState.uploaded => theme.colorScheme.primary,
    MediaTransferState.failed => theme.colorScheme.error,
  };
}

IconData _iconForTransferKind(MediaTransferKind kind) {
  return switch (kind) {
    MediaTransferKind.photo => Icons.photo_outlined,
    MediaTransferKind.video => Icons.videocam_outlined,
    MediaTransferKind.file => Icons.insert_drive_file_outlined,
    MediaTransferKind.location => Icons.location_on_outlined,
    MediaTransferKind.voiceNote => Icons.mic_none_rounded,
    MediaTransferKind.statusPhoto => Icons.photo_camera_back_outlined,
    MediaTransferKind.statusVideo => Icons.ondemand_video_outlined,
  };
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Not yet';
  }

  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
