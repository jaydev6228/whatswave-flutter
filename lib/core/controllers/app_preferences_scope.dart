import 'package:flutter/widgets.dart';

import 'app_preferences_controller.dart';

/// Makes [AppPreferencesController] reachable from anywhere in the tree.
///
/// Exists because preferences are read in places far from where they are
/// edited -- the call screen needs `mirrorSelfView` but is pushed with only
/// a CallsController, and threading a second argument through every route
/// for one boolean is worse than an inherited lookup.
///
/// InheritedNotifier rather than InheritedWidget: the controller is a
/// ChangeNotifier, so dependents rebuild when a preference changes without
/// anyone wiring up a listener.
class AppPreferencesScope extends InheritedNotifier<AppPreferencesController> {
  const AppPreferencesScope({
    required AppPreferencesController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppPreferencesController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppPreferencesScope>();
    assert(scope != null, 'No AppPreferencesScope above this widget.');
    return scope!.notifier!;
  }

  /// For places that can sensibly carry on without preferences, such as a
  /// widget test that pumps a screen in isolation.
  static AppPreferencesController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppPreferencesScope>()
        ?.notifier;
  }
}
