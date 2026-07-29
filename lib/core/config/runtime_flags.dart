import 'package:flutter/foundation.dart';

const bool _kRequestedDemoSurfaces = bool.fromEnvironment(
  'WW_ENABLE_DEMO_SURFACES',
  defaultValue: true,
);

/// Demo and QA-only surfaces are never allowed in release or TestFlight builds.
const bool kEnableDemoSurfaces = !kReleaseMode && _kRequestedDemoSurfaces;

/// Seeded session restore is also restricted to non-release builds.
const bool kEnableDemoRestoreSession =
    !kReleaseMode && bool.fromEnvironment('WW_DEMO_RESTORE_SESSION');
