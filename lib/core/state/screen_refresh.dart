import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/customer_repository.dart';

/// Which of the shell's tabs the customer is actually looking at.
///
/// The shell keeps all five tabs alive in an [IndexedStack] so each holds its
/// scroll offset and half-typed forms — which also means the four behind the
/// visible one are fully built, mounted widgets that could happily fire a
/// network request nobody asked for. This is how a screen tells whether it is
/// the one being read, so a stale tab can wait until it is opened instead of
/// re-loading five screens every time a notification lands.
///
/// Absent outside the shell — Notifications, Referrals and Settings are pushed
/// routes, and a pushed route is on top whenever it exists at all — in which
/// case [maybeOf] answers null and [ScreenRefresh] treats the screen as visible.
class VisibleTab extends InheritedNotifier<ValueNotifier<int>> {
  const VisibleTab({
    super.key,
    required ValueNotifier<int> index,
    required super.child,
  }) : super(notifier: index);

  /// The tab on screen, or null when this widget is not under a shell.
  ///
  /// Registers the caller as a dependent, so a tab change rebuilds it — that
  /// rebuild is what wakes a stale screen the moment it is opened.
  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VisibleTab>()?.notifier?.value;
}

/// Keeps one screen's data honest while the app stays open.
///
/// THE PROBLEM THIS SOLVES. Every screen here loads a `Future` once in
/// `initState` and hands it to a `FutureBuilder`; nothing re-reads it. Combined
/// with the shell's IndexedStack, which never disposes a tab, the first answer a
/// screen received was the only answer it ever showed. The office publishing a
/// document, confirming a lead or moving a project along reached the phone as a
/// notification — and the screen that notification pointed at still read "No
/// documents yet" until the customer killed the app and opened it again, which
/// is not a fix a customer should have to know about.
///
/// Three things now make a screen re-read, in the order they matter:
///
///   * **News.** [CustomerRepository.revision] is bumped when a notification
///     arrives or the app returns to the foreground. The visible screen reloads
///     at once; the ones behind it are marked stale and reload when opened.
///   * **Age.** Opening a tab whose data is older than [freshFor] re-reads it.
///     Not every change the office makes sends a notification — issuing an app
///     login against an existing lead sends none — so arriving at a screen is
///     itself a good moment to ask again.
///   * **The customer asking.** Pull-to-refresh and the error screen's Retry,
///     which go through [refreshNow] so they also reset the clock.
///
/// A screen adopts it by naming its tab and its loader:
///
/// ```dart
/// class _DocsState extends State<Docs> with ScreenRefresh {
///   @override int? get refreshTab => ShellTab.docs;
///   @override Future<void> loadData() async {
///     setState(() => _future = _read());
///     await _future;
///   }
/// }
/// ```
mixin ScreenRefresh<T extends StatefulWidget> on State<T> {
  /// The shell tab this screen sits on, or null for a pushed route — which is
  /// on top whenever it is mounted, so it is always treated as visible.
  int? get refreshTab => null;

  /// Re-read this screen's data. Must set whatever the build reads, and await it.
  Future<void> loadData();

  /// How long a loaded screen is trusted without asking again.
  ///
  /// A minute: long enough that flicking between tabs does not re-query the
  /// server on every tap, short enough that a customer who puts the phone down,
  /// takes a call and comes back is not reading a stale answer.
  Duration get freshFor => const Duration(minutes: 1);

  /// Held from [didChangeDependencies] rather than read again in [dispose],
  /// where looking anything up on the context is no longer safe.
  CustomerRepository? _repo;

  DateTime _loadedAt = DateTime.now();
  bool _stale = false;
  bool _reloading = false;

  /// The last tab index seen from the tree.
  ///
  /// CACHED, not read on demand: `VisibleTab.maybeOf` registers an inherited
  /// dependency, and that may only happen during build or
  /// [didChangeDependencies]. Calling it from the revision listener — which
  /// fires whenever a notification lands, at no particular point in the frame —
  /// trips Flutter's assertion and the reload never happens, which is precisely
  /// the bug this mixin exists to fix.
  int? _visibleTab;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_repo == null) {
      _repo = context.read<CustomerRepository>();
      _repo!.revision.addListener(_onNews);
    }

    // Reading the tab here is what subscribes this screen to tab changes.
    _visibleTab = VisibleTab.maybeOf(context);
    _considerReload();
  }

  @override
  void dispose() {
    _repo?.revision.removeListener(_onNews);
    super.dispose();
  }

  /// Something changed server-side. Reload now if this screen is being read.
  void _onNews() {
    if (!mounted) return;
    _stale = true;
    _considerReload();
  }

  void _considerReload() {
    final tab = refreshTab;
    final visible = tab == null || _visibleTab == null || _visibleTab == tab;
    if (!visible || _reloading) return;

    final aged = DateTime.now().difference(_loadedAt) >= freshFor;
    if (!_stale && !aged) return;

    // Deferred to a microtask, not run inline: this is reached from
    // didChangeDependencies — which the framework calls in the middle of
    // building — and `loadData` sets state. A microtask queued during a build
    // runs once that frame's synchronous work is finished, which is the first
    // safe moment.
    //
    // NOT a post-frame callback: registering one does not schedule a frame, so
    // on a settled tree — a screen sitting on "No documents yet", waiting,
    // which is exactly when the news arrives — the callback simply never ran.
    _reloading = true;
    Future<void>.microtask(() async {
      if (!mounted) {
        _reloading = false;
        return;
      }
      await refreshNow().whenComplete(() => _reloading = false);
    });
  }

  /// Re-read now, and treat the screen as fresh from this moment.
  ///
  /// The one entry point: pull-to-refresh, Retry and the automatic paths all go
  /// through here, so none of them can reload without resetting the clock.
  Future<void> refreshNow() async {
    _stale = false;
    _loadedAt = DateTime.now();
    await loadData();
  }
}
