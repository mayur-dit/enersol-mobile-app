import 'package:flutter/foundation.dart';

/// The handle a screen pushed OVER the shell uses to drive the shell beneath it.
///
/// The five tabs live inside [AppShell]'s own `State`, and a pushed route is a
/// SIBLING of the shell in the same Navigator, not a descendant — so it cannot
/// reach that state through the element tree, however far up it looks. This
/// object is provided above the Navigator instead; the shell attaches itself to
/// it on mount, and pushed screens ask it to switch tabs.
///
/// It is deliberately tiny and not a [ChangeNotifier]: nothing rebuilds on the
/// strength of it, it only forwards one call.
class ShellController {
  ValueChanged<int>? _selectTab;

  /// Called by [AppShell] as it mounts.
  void attach(ValueChanged<int> selectTab) => _selectTab = selectTab;

  /// Called by [AppShell] as it goes. Guarded on identity so a shell that is
  /// replaced (a sign-out and a fresh sign-in) cannot have its successor's
  /// handler torn out from under it by the old one's `dispose`.
  void detach(ValueChanged<int> selectTab) {
    if (identical(_selectTab, selectTab)) _selectTab = null;
  }

  /// Switches the shell to a footer tab. A no-op when there is no shell — the
  /// login screen is the only time that is true.
  void openTab(int index) => _selectTab?.call(index);
}
