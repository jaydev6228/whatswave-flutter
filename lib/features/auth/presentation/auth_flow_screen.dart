import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/config/runtime_flags.dart';
import '../application/auth_controller.dart';
import '../data/country_dial_codes.dart';

class AuthFlowScreen extends StatelessWidget {
  const AuthFlowScreen({
    required this.controller,
    super.key,
  });

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isCompact = _useCompactAuthLayout(context);
        final usePinnedPrimaryAction = isCompact;
        final theme = Theme.of(context);
        final palette = _stepPalette(theme, controller.step);

        final bottomSafeInset = MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                final content = SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    isCompact ? 12 : 24,
                    20,
                    usePinnedPrimaryAction
                        ? 16
                        : (isCompact ? 24 : 32) + bottomSafeInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AuthHeader(
                        step: controller.step,
                        icon: palette.$1,
                        color: palette.$2,
                        isCompact: isCompact,
                      ),
                      SizedBox(height: isCompact ? 12 : 24),
                      if (controller.statusMessage != null &&
                          controller.step == AuthStep.profileSetup)
                        Padding(
                          padding: EdgeInsets.only(bottom: isCompact ? 12 : 16),
                          child: _FeedbackBanner(
                            icon: Icons.check_circle_outline_rounded,
                            message: controller.statusMessage!,
                            color: theme.colorScheme.primary,
                            isCompact: isCompact,
                          ),
                        ),
                      if (controller.errorMessage != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: isCompact ? 12 : 16),
                          child: _FeedbackBanner(
                            icon: Icons.error_outline_rounded,
                            message: controller.errorMessage!,
                            color: theme.colorScheme.error,
                            isCompact: isCompact,
                          ),
                        ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: switch (controller.step) {
                          AuthStep.phoneEntry => _PhoneEntryCard(
                              key: const ValueKey('phone_entry_card'),
                              controller: controller,
                              isCompact: isCompact,
                              showInlinePrimaryAction: !usePinnedPrimaryAction,
                            ),
                          AuthStep.otpEntry => _OtpEntryCard(
                              key: const ValueKey('otp_entry_card'),
                              controller: controller,
                              isCompact: isCompact,
                              showInlinePrimaryAction: !usePinnedPrimaryAction,
                            ),
                          AuthStep.profileSetup => _ProfileBootstrapCard(
                              key: const ValueKey('profile_setup_card'),
                              controller: controller,
                              isCompact: isCompact,
                              showInlinePrimaryAction: !usePinnedPrimaryAction,
                            ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ],
                  ),
                );

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: usePinnedPrimaryAction
                        ? SizedBox(
                            height: viewportConstraints.maxHeight,
                            child: Column(
                              children: [
                                Expanded(child: content),
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    20,
                                    16 + bottomSafeInset,
                                  ),
                                  child: _AuthPrimaryActionButton(
                                    controller: controller,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : content,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  (IconData, Color) _stepPalette(ThemeData theme, AuthStep step) {
    return switch (step) {
      AuthStep.phoneEntry => (
          Icons.phone_iphone_rounded,
          theme.colorScheme.primary
        ),
      AuthStep.otpEntry => (Icons.lock_open_rounded, AppPalette.sky),
      AuthStep.profileSetup => (Icons.badge_rounded, AppPalette.amber),
      _ => (Icons.chat_bubble_rounded, theme.colorScheme.primary),
    };
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.step,
    required this.icon,
    required this.color,
    required this.isCompact,
  });

  final AuthStep step;
  final IconData icon;
  final Color color;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = switch (step) {
      AuthStep.phoneEntry => (
          title: 'Welcome to WhatsWave',
          subtitle:
              'Use your phone number to restore your chats and continue on this device.'
        ),
      AuthStep.otpEntry => (
          title: 'Verify your number',
          // No subtitle here -- the OTP card right below already states
          // exactly what code was sent and where, so a generic "we sent a
          // code" line above it would just repeat the same fact.
          subtitle: null,
        ),
      AuthStep.profileSetup => (
          title: 'Set up your profile',
          subtitle:
              'Choose the name and about line people will see when you join chats, calls, and groups.'
        ),
      _ => (
          title: 'WhatsWave',
          subtitle:
              'A calm, reliable messaging experience built in small, reviewable phases.'
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isCompact ? 24 : 28,
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, color: color, size: isCompact ? 24 : 28),
        ),
        SizedBox(width: isCompact ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: isCompact ? 22 : null,
                  height: isCompact ? 1.05 : null,
                ),
              ),
              if (copy.subtitle != null) ...[
                SizedBox(height: isCompact ? 4 : 6),
                Text(
                  copy.subtitle!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    fontSize: isCompact ? 16 : null,
                    height: isCompact ? 1.34 : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.isCompact,
  });

  final IconData icon;
  final String message;
  final Color color;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isCompact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: isCompact ? 14 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneEntryCard extends StatefulWidget {
  const _PhoneEntryCard({
    required this.controller,
    required this.isCompact,
    required this.showInlinePrimaryAction,
    super.key,
  });

  final AuthController controller;
  final bool isCompact;
  final bool showInlinePrimaryAction;

  @override
  State<_PhoneEntryCard> createState() => _PhoneEntryCardState();
}

class _PhoneEntryCardState extends State<_PhoneEntryCard> {
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _phoneController =
        TextEditingController(text: widget.controller.phoneNumber);
    _phoneController.addListener(_handlePhoneChanged);
    widget.controller.detectCountryFromDeviceLocation();
  }

  @override
  void didUpdateWidget(covariant _PhoneEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_phoneController.text != widget.controller.phoneNumber) {
      _phoneController.value = TextEditingValue(
        text: widget.controller.phoneNumber,
        selection: TextSelection.collapsed(
          offset: widget.controller.phoneNumber.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneController
      ..removeListener(_handlePhoneChanged)
      ..dispose();
    super.dispose();
  }

  void _handlePhoneChanged() {
    widget.controller.updatePhoneNumber(_phoneController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = widget.isCompact ? 16.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone number',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: widget.isCompact ? 18 : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We detected a country code for this device. Change it if this number belongs somewhere else, then enter the phone number for SMS verification.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: widget.isCompact ? 15 : null,
            height: widget.isCompact ? 1.32 : null,
          ),
        ),
        SizedBox(height: spacing),
        LayoutBuilder(
          builder: (context, constraints) {
            final useStackedFields = constraints.maxWidth < 340;
            final countryField = _CountryCodeField(
              controller: widget.controller,
              isCompact: widget.isCompact,
            );
            final phoneField = TextField(
              key: const Key('auth_phone_field'),
              controller: _phoneController,
              enabled: !widget.controller.isBusy,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.controller.requestOtp(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\s()-]')),
              ],
              decoration: InputDecoration(
                isDense: widget.isCompact,
                labelText: 'Phone number',
                hintText: 'Mobile number',
              ),
            );

            if (useStackedFields) {
              return Column(
                children: [
                  countryField,
                  const SizedBox(height: 12),
                  phoneField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: widget.isCompact ? 116 : 132,
                  child: countryField,
                ),
                const SizedBox(width: 12),
                Expanded(child: phoneField),
              ],
            );
          },
        ),
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('auth_send_code_button'),
              onPressed: widget.controller.isBusy
                  ? null
                  : widget.controller.requestOtp,
              child: widget.controller.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Send code'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CountryCodeField extends StatelessWidget {
  const _CountryCodeField({
    required this.controller,
    required this.isCompact,
  });

  final AuthController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButtonFormField<CountryDialCode>(
      key: const Key('auth_country_code_field'),
      initialValue: controller.selectedCountry,
      isExpanded: true,
      menuMaxHeight: 420,
      borderRadius: BorderRadius.circular(20),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(
        isDense: isCompact,
        labelText: 'Code',
      ),
      selectedItemBuilder: (context) {
        // Just the dial code once selected -- the country name is already
        // spelled out per row in the dropdown list below, so the ISO
        // letters here would be a second, terser way of saying the same
        // thing.
        return controller.availableCountries.map((country) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              country.dialCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(growable: false);
      },
      items: controller.availableCountries.map((country) {
        return DropdownMenuItem<CountryDialCode>(
          value: country,
          child: Text(
            '${country.name} (${country.dialCode})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(growable: false),
      onChanged: controller.isBusy
          ? null
          : (country) {
              if (country != null) {
                controller.updateCountryDialCode(country);
              }
            },
    );
  }
}

class _OtpEntryCard extends StatefulWidget {
  const _OtpEntryCard({
    required this.controller,
    required this.isCompact,
    required this.showInlinePrimaryAction,
    super.key,
  });

  final AuthController controller;
  final bool isCompact;
  final bool showInlinePrimaryAction;

  @override
  State<_OtpEntryCard> createState() => _OtpEntryCardState();
}

class _OtpEntryCardState extends State<_OtpEntryCard> {
  late final TextEditingController _otpController;

  @override
  void initState() {
    super.initState();
    _otpController = TextEditingController(text: widget.controller.otpCode);
    _otpController.addListener(_handleOtpChanged);
  }

  @override
  void didUpdateWidget(covariant _OtpEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_otpController.text != widget.controller.otpCode) {
      _otpController.value = TextEditingValue(
        text: widget.controller.otpCode,
        selection:
            TextSelection.collapsed(offset: widget.controller.otpCode.length),
      );
    }
  }

  @override
  void dispose() {
    _otpController
      ..removeListener(_handleOtpChanged)
      ..dispose();
    super.dispose();
  }

  void _handleOtpChanged() {
    widget.controller.updateOtpCode(_otpController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = widget.isCompact ? 16.0 : 20.0;
    final helperText = kEnableDemoSurfaces ? 'QA code: 123456' : null;
    final hintText = kEnableDemoSurfaces ? '123456' : '6-digit code';
    final message = kEnableDemoSurfaces
        ? 'A code was sent to ${widget.controller.maskedPhoneNumber}. Use 123456 in this QA build to continue.'
        : 'A code was sent to ${widget.controller.maskedPhoneNumber}. Enter the 6-digit code to continue.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '6-digit verification code',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: widget.isCompact ? 18 : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: widget.isCompact ? 15 : null,
            height: widget.isCompact ? 1.32 : null,
          ),
        ),
        SizedBox(height: spacing),
        TextField(
          key: const Key('auth_otp_field'),
          controller: _otpController,
          enabled: !widget.controller.isBusy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.controller.verifyOtp(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: 'Code',
            hintText: hintText,
            helperText: helperText,
          ),
        ),
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('auth_verify_code_button'),
              onPressed:
                  widget.controller.isBusy ? null : widget.controller.verifyOtp,
              child: widget.controller.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Verify code'),
            ),
          ),
        ],
        SizedBox(height: widget.isCompact ? 8 : 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              key: const Key('auth_resend_code_button'),
              onPressed:
                  widget.controller.isBusy ? null : widget.controller.resendOtp,
              child: const Text('Resend code'),
            ),
            TextButton(
              key: const Key('auth_change_number_button'),
              onPressed: widget.controller.isBusy
                  ? null
                  : widget.controller.editPhoneNumber,
              child: const Text('Change number'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileBootstrapCard extends StatefulWidget {
  const _ProfileBootstrapCard({
    required this.controller,
    required this.isCompact,
    required this.showInlinePrimaryAction,
    super.key,
  });

  final AuthController controller;
  final bool isCompact;
  final bool showInlinePrimaryAction;

  @override
  State<_ProfileBootstrapCard> createState() => _ProfileBootstrapCardState();
}

class _ProfileBootstrapCardState extends State<_ProfileBootstrapCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _aboutController;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.controller.displayName);
    _aboutController = TextEditingController(text: widget.controller.about);
    _nameController.addListener(_handleNameChanged);
    _aboutController.addListener(_handleAboutChanged);
  }

  @override
  void didUpdateWidget(covariant _ProfileBootstrapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_nameController.text != widget.controller.displayName) {
      _nameController.value = TextEditingValue(
        text: widget.controller.displayName,
        selection: TextSelection.collapsed(
          offset: widget.controller.displayName.length,
        ),
      );
    }
    if (_aboutController.text != widget.controller.about) {
      _aboutController.value = TextEditingValue(
        text: widget.controller.about,
        selection:
            TextSelection.collapsed(offset: widget.controller.about.length),
      );
    }
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    _aboutController
      ..removeListener(_handleAboutChanged)
      ..dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    widget.controller.updateDisplayName(_nameController.text);
  }

  void _handleAboutChanged() {
    widget.controller.updateAbout(_aboutController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = widget.isCompact ? 16.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: widget.isCompact ? 24 : 28,
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.16),
              child: Text(
                widget.controller.profilePreviewLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(width: widget.isCompact ? 12 : 16),
            Expanded(
              child: Text(
                'You are verified as ${widget.controller.maskedPhoneNumber}. Add the profile details that will carry through chats, groups, and calls.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  fontSize: widget.isCompact ? 15 : null,
                  height: widget.isCompact ? 1.32 : null,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing),
        TextField(
          key: const Key('auth_name_field'),
          controller: _nameController,
          enabled: !widget.controller.isBusy,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'Jay Devra',
          ),
        ),
        SizedBox(height: widget.isCompact ? 12 : 16),
        TextField(
          key: const Key('auth_about_field'),
          controller: _aboutController,
          enabled: !widget.controller.isBusy,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'About',
            hintText:
                'Building calm, reliable chat products one release at a time.',
          ),
        ),
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('auth_finish_profile_button'),
              onPressed: widget.controller.isBusy
                  ? null
                  : widget.controller.completeProfile,
              child: widget.controller.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Finish setup'),
            ),
          ),
        ],
      ],
    );
  }
}

class _AuthPrimaryActionButton extends StatelessWidget {
  const _AuthPrimaryActionButton({
    required this.controller,
  });

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final (key, label, onPressed) = switch (controller.step) {
      AuthStep.phoneEntry => (
          const Key('auth_send_code_button'),
          'Send code',
          controller.requestOtp,
        ),
      AuthStep.otpEntry => (
          const Key('auth_verify_code_button'),
          'Verify code',
          controller.verifyOtp,
        ),
      AuthStep.profileSetup => (
          const Key('auth_finish_profile_button'),
          'Finish setup',
          controller.completeProfile,
        ),
      _ => (
          const Key('auth_primary_action_button'),
          'Continue',
          () {},
        ),
    };

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: key,
        onPressed: controller.isBusy ? null : onPressed,
        child: controller.isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(label),
      ),
    );
  }
}

bool _useCompactAuthLayout(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  final availableHeight = mediaQuery.size.height - mediaQuery.padding.vertical;
  return availableHeight < 700;
}
