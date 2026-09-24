import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/config/runtime_flags.dart';
import '../../shared/widgets/glass_text_field.dart';
import '../../shared/widgets/liquid_glass.dart';
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

        final form = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AuthHeader(
              step: controller.step,
              icon: palette.$1,
              color: palette.$2,
              isCompact: isCompact,
            ),
            SizedBox(height: isCompact ? 16 : 24),
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
        );

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                final scrollPadding = EdgeInsets.fromLTRB(
                  20,
                  isCompact ? 16 : 24,
                  20,
                  usePinnedPrimaryAction
                      ? 16
                      : (isCompact ? 24 : 32) + bottomSafeInset,
                );

                Widget scrollable({required double minHeight}) {
                  return SingleChildScrollView(
                    padding: scrollPadding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (minHeight - scrollPadding.vertical)
                            .clamp(0, double.infinity),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: form,
                        ),
                      ),
                    ),
                  );
                }

                if (usePinnedPrimaryAction) {
                  return Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return scrollable(
                              minHeight: constraints.maxHeight,
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          16 + bottomSafeInset,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: _AuthPrimaryActionButton(
                              controller: controller,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return scrollable(
                  minHeight: viewportConstraints.maxHeight,
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

    return Column(
      children: [
        LiquidGlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          blurred: false,
          showShadow: false,
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 12 : 14),
            child: Icon(icon, color: color, size: isCompact ? 24 : 28),
          ),
        ),
        SizedBox(height: isCompact ? 14 : 16),
        Text(
          copy.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: isCompact ? 22 : null,
            height: isCompact ? 1.15 : null,
          ),
        ),
        if (copy.subtitle != null) ...[
          SizedBox(height: isCompact ? 6 : 8),
          Text(
            copy.subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: isCompact ? 16 : null,
              height: isCompact ? 1.34 : null,
            ),
          ),
        ],
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

    return LiquidGlassSurface(
      blurred: false,
      showShadow: false,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      color: color.withValues(alpha: 0.14),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isCompact ? 12 : 14,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Phone number',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: widget.isCompact ? 18 : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We detected a country code for this device. Change it if this number belongs somewhere else, then enter the phone number for SMS verification.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: widget.isCompact ? 15 : null,
            height: widget.isCompact ? 1.32 : null,
          ),
        ),
        SizedBox(height: spacing),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CountryCodeField(controller: widget.controller),
              const SizedBox(width: 10),
              Expanded(
                child: GlassTextField(
                  fieldKey: const Key('auth_phone_field'),
                  controller: _phoneController,
                  enabled: !widget.controller.isBusy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  hintText: 'Phone number',
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\s()-]')),
                  ],
                  onSubmitted: (_) => widget.controller.requestOtp(),
                ),
              ),
            ],
          ),
        ),
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          _AuthPrimaryActionButton(controller: widget.controller),
        ],
      ],
    );
  }
}

class _CountryCodeField extends StatelessWidget {
  const _CountryCodeField({
    required this.controller,
  });

  final AuthController controller;

  Future<void> _openPicker(BuildContext anchorContext) async {
    final selected = await showLiquidGlassBubbleMenu<CountryDialCode>(
      anchorContext: anchorContext,
      openBelow: true,
      itemBuilder: (context) => [
        for (final country in controller.availableCountries)
          LiquidGlassBubbleItem(
            label: '${country.name} (${country.dialCode})',
            selected: country == controller.selectedCountry,
            onTap: () => Navigator.of(context).pop(country),
          ),
      ],
    );
    if (selected != null) {
      controller.updateCountryDialCode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Builder(
      builder: (anchorContext) {
        return LiquidGlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          blurred: false,
          showShadow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('auth_country_code_field'),
              onTap:
                  controller.isBusy ? null : () => _openPicker(anchorContext),
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.selectedCountry.dialCode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.64),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '6-digit verification code',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: widget.isCompact ? 18 : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: widget.isCompact ? 15 : null,
            height: widget.isCompact ? 1.32 : null,
          ),
        ),
        SizedBox(height: spacing),
        GlassTextField(
          fieldKey: const Key('auth_otp_field'),
          controller: _otpController,
          enabled: !widget.controller.isBusy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          hintText: hintText,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => widget.controller.verifyOtp(),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 8),
          Text(
            helperText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          _AuthPrimaryActionButton(controller: widget.controller),
        ],
        SizedBox(height: widget.isCompact ? 8 : 12),
        Wrap(
          alignment: WrapAlignment.center,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'You are verified as ${widget.controller.maskedPhoneNumber}. Add the profile details that will carry through chats, groups, and calls.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: widget.isCompact ? 15 : null,
            height: widget.isCompact ? 1.32 : null,
          ),
        ),
        SizedBox(height: spacing),
        Center(
          child: LiquidGlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            blurred: false,
            showShadow: false,
            child: Padding(
              padding: EdgeInsets.all(widget.isCompact ? 12 : 14),
              child: Text(
                widget.controller.profilePreviewLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: spacing),
        GlassTextField(
          fieldKey: const Key('auth_name_field'),
          controller: _nameController,
          enabled: !widget.controller.isBusy,
          textInputAction: TextInputAction.next,
          hintText: 'Display name',
        ),
        SizedBox(height: widget.isCompact ? 12 : 16),
        GlassTextField(
          fieldKey: const Key('auth_about_field'),
          controller: _aboutController,
          enabled: !widget.controller.isBusy,
          minLines: 2,
          maxLines: 3,
          hintText:
              'Building calm, reliable chat products one release at a time.',
        ),
        if (widget.showInlinePrimaryAction) ...[
          SizedBox(height: spacing),
          _AuthPrimaryActionButton(controller: widget.controller),
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

    return GlassPrimaryButton(
      actionKey: key,
      label: label,
      fullWidth: true,
      isLoading: controller.isBusy,
      onPressed: controller.isBusy ? null : onPressed,
    );
  }
}

bool _useCompactAuthLayout(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  final availableHeight = mediaQuery.size.height - mediaQuery.padding.vertical;
  return availableHeight < 700;
}
