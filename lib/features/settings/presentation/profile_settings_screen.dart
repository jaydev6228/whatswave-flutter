import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> _saveProfile() async {
    final didSave = await widget.authController.updateCurrentProfile(
      name: _nameController.text,
      about: _aboutController.text,
    );
    if (!mounted || !didSave) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) {
      return;
    }
    await widget.authController.updateAvatar(File(picked.path));
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
                onPressed: widget.authController.isBusy ? null : _saveProfile,
                child: widget.authController.isBusy
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
                              onTap: widget.authController.isBusy
                                  ? null
                                  : _changeAvatar,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AvatarBadge(
                                    label: currentUser.avatarLabel,
                                    color: currentUser.accentColor,
                                    avatarUrl: currentUser.avatarUrl,
                                    size: 70,
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme.colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.camera_alt_rounded,
                                        size: 14,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
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
