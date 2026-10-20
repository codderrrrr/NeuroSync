import 'package:flutter/widgets.dart';

/// Provides the application's controllers to the widget tree.
///
/// A plain [InheritedWidget] is enough here: widgets listen to the controllers
/// they care about with [ListenableBuilder], so rebuilds stay scoped to the
/// parts of the screen that actually change.
///
/// The scope never changes after build, so [updateShouldNotify] is always
/// false and the subtree is not rebuilt because the scope was replaced.
abstract class AppScopeBase extends InheritedWidget {
  const AppScopeBase({super.key, required super.child});

  @override
  bool updateShouldNotify(AppScopeBase oldWidget) => false;
}
