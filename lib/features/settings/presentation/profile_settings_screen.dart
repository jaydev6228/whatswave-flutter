import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/media/avatar_photo_picker.dart';
import '../../../core/models/app_user.dart';
import '../../../features/auth/application/auth_controller.dart';
import '../../shared/widgets/avatar_badge.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    required this.authController,
    required this.currentUser,
    super.key,
  });

  final AuthController authController;
  final AppUser currentUser;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _aboutController;

  /// A picked-but-not-yet-saved photo -- previewed locally, but not
  /// uploaded (and the real profile photo not replaced) until Save is
  /// tapped, matching how the name/about fields already stage edits in
  /// their own TextEditingControllers rather than writing on every
  /// keystroke.
  File? _pendingAvatarFile;
  bool _pendingRemoveAvatar = false;
  bool _isSavingAvatar = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.name);
    _aboutController = TextEditingController(text: widget.currentUser.about);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  bool get _isBusy => widget.authController.isBusy || _isSavingAvatar;

  Future<void> _saveProfile() async {
    if (_pendingRemoveAvatar) {
      setState(() => _isSavingAvatar = true);
      final didRemove = await widget.authController.deleteAvatar();
      if (!mounted) {
        return;
      }
      setState(() => _isSavingAvatar = false);
      if (!didRemove) {
        return;
      }
      _pendingRemoveAvatar = false;
    }

    final pendingAvatar = _pendingAvatarFile;
    if (pendingAvatar != null) {
      setState(() => _isSavingAvatar = true);
      final didUploadAvatar =
          await widget.authController.updateAvatar(pendingAvatar);
      if (!mounted) {
        return;
      }
      setState(() => _isSavingAvatar = false);
      if (!didUploadAvatar) {
        // Leaves the local preview + error message in place so the user
        // can see what failed and retry via Save again, instead of
        // silently discarding the photo they picked.
        return;
      }
      _pendingAvatarFile = null;
    }

    final didSave = await widget.authController.updateCurrentProfile(
      name: _nameController.text,
      about: _aboutController.text,
    );
    if (!mounted || !didSave) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _showAvatarPhotoOptions(AppUser currentUser) async {
    final canRemove = _pendingAvatarFile != null ||
        _pendingRemoveAvatar ||
        currentUser.avatarUrl?.isNotEmpty == true;
    final action = await showAvatarPhotoOptionsSheet(
      context,
      canRemove: canRemove,
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case AvatarPhotoSheetAction.choose:
        final cropped = await pickAndCropAvatarPhoto(context);
        if (!mounted || cropped == null) {
          return;
        }
        setState(() {
          _pendingAvatarFile = cropped;
          _pendingRemoveAvatar = false;
        });
      case AvatarPhotoSheetAction.remove:
        setState(() {
          _pendingAvatarFile = null;
          _pendingRemoveAvatar = true;
        });
    }
  }

  Widget _buildAvatarPreview(AppUser currentUser) {
    if (_pendingAvatarFile != null) {
      return ClipOval(
        child: Image.file(
          _pendingAvatarFile!,
          width: 70,
          height: 70,
          fit: BoxFit.cover,
        ),
      );
    }
    if (_pendingRemoveAvatar) {
      return AvatarBadge(
        label: currentUser.avatarLabel,
        color: currentUser.accentColor,
        size: 70,
      );
    }
    return AvatarBadge(
      label: currentUser.avatarLabel,
      color: currentUser.accentColor,
      avatarUrl: currentUser.avatarUrl,
      size: 70,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final currentUser =
            widget.authController.currentUser ?? widget.currentUser;

        return Scaffold(
          key: const Key('profile_settings_screen'),
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              TextButton(
                key: const Key('profile_save_button'),
                onPressed: _isBusy ? null : _saveProfile,
                child: _isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              key: const Key('profile_avatar_change_button'),
                              onTap: _isBusy
                                  ? null
                                  : () => _showAvatarPhotoOptions(currentUser),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _buildAvatarPreview(currentUser),
                                  AvatarCameraBadge(isBusy: _isSavingAvatar),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your profile',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Keep your saved name and about line current so relaunches feel like the same account every time.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.22),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('profile_name_field'),
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            hintText: 'How people will see you',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('profile_about_field'),
                          controller: _aboutController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'About',
                            hintText: 'A short line for your profile',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          key: const Key('profile_phone_tile'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(
                              alpha: theme.brightness == Brightness.dark
                                  ? 0.18
                                  : 0.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.phone_iphone_rounded,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.62),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Phone number',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      currentUser.phoneNumber,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.72),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.authController.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            widget.authController.errorMessage!,
                            key: const Key('profile_error_text'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
