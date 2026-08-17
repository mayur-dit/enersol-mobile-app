import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/notification.dart';
import '../realtime/push_service.dart';
import '../realtime/ws_client.dart';
import 'auth_service.dart';

/// The customer's notification inbox, and the two ways one reaches them.
///
/// ONE INBOX, THREE APPS. `ens_notifications` is shared with the admin panel
/// and the engineer PWA — the backend writes one row per RECIPIENT, so a
/// customer is not a special case anywhere in the pipeline. This app reads its
/// rows through `/customer-portal`, the single door it holds a grant for, which
/// scopes every read to the signed-in user server-side.
///
/// DELIVERY IS DELIBERATELY DOUBLED:
///   * the WebSocket lights the bell while the app is open — the moment a
///     customer is watching the Service screen is exactly the moment their
///     request gets resolved, and FCM shows nothing to a foreground app;
///   * FCM reaches the phone when the app is closed, which is most of the time.
///
/// Both are best-effort and neither is trusted as the record: a push only
/// prompts a re-read. `refresh()` on resume is the backstop that makes a
/// dropped socket and a blocked push indistinguishable from "nothing happened".
class NotificationService extends ChangeNotifier {
  NotificationService(this._api, this._auth, {this.onNews}) {
    _auth.addListener(_onAuthChanged);
  }

  final ApiClient _api;
  final AuthService _auth;

  /// Told whenever a notification reaches this device, by any route.
  ///
  /// A notification is the office saying it just changed something about this
  /// customer's job, so it is also the best signal the screens will ever get
  /// that what they are showing is out of date. Wired to
  /// `CustomerRepository.invalidate` in main — a callback rather than a direct
  /// dependency, because this service is deliberately built above the
  /// repository and must not start reaching into it.
  final VoidCallback? onNews;

  final WsClient _ws = WsClient();
  final PushService _push = PushService();

  StreamSubscription<AppNotification>? _wsSub;
  StreamSubscription<void>? _pushSub;
  StreamSubscription<Map<String, dynamic>>? _openSub;

  List<AppNotification> _items = const [];
  List<AppNotification> get items => _items;

  int _unread = 0;

  /// Drives the badge. Kept as its own count rather than derived from [items],
  /// which holds only the most recent page — a customer with a backlog would
  /// otherwise see a badge that stops at 30.
  int get unread => _unread;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool _started = false;

  /// Live connection state, for the header's delivery-health dot.
  ValueListenable<WsStatus> get connection => _ws.status;

  /// True when both paths are healthy — the green tick beside the bell.
  bool get deliveryHealthy => _ws.isLive || _push.working;

  /// FCM holds a token for this device, so a closed app can still be reached.
  /// Separate from [deliveryHealthy] because the two failures need different
  /// answers: a dead socket fixes itself on the next resume, a missing push
  /// token usually means a permission the user has to grant.
  bool get pushWorking => _push.working;

  /// The socket alone, for a status line that has to name which half is down.
  bool get socketLive => _ws.isLive;

  /// This platform can receive push at all — false on desktop/web builds.
  bool get pushSupported => _push.supportedPlatform;

  /// Set when push is off because THIS BUILD was never finished — the Firebase
  /// app for the platform is not registered. Distinct from a permission the
  /// user declined, and the difference matters: one is fixed in the phone's
  /// settings, the other cannot be fixed on the phone at all.
  String get pushSetupNote => _push.setupNote;

  /// Deep links from a TAPPED push, for the shell to route on.
  final _routes = StreamController<String>.broadcast();
  Stream<String> get routes => _routes.stream;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Begin, once there is a session. Idempotent — the shell calls it on build
  /// and again on every resume.
  Future<void> start() async {
    if (!_auth.isAuthenticated) return;
    if (_started) {
      await refresh();
      _connect();
      return;
    }
    _started = true;

    _wsSub = _ws.notifications.listen(_receive);
    _pushSub = _push.arrived.listen((_) {
      refresh();
      onNews?.call();
    });
    _openSub = _push.opened.listen((data) {
      final url = '${data['url'] ?? ''}'.trim();
      if (url.isNotEmpty) _routes.add(url);
      // A tap means the user has seen it; the list may not even be loaded yet,
      // so re-read rather than trying to patch a row we might not hold.
      refresh();
      // The tap is about to open the screen the notification names, and that
      // screen has been sitting mounted behind the shell since sign-in.
      onNews?.call();
    });

    _connect();
    await refresh();

    // Registering the token is what makes the phone reachable at all, and it
    // goes through the portal rather than /register-push-token: this app holds
    // exactly one transport grant by design.
    await _push.start(onToken: _registerToken);
  }

  /// Re-run the WHOLE delivery setup, including the push half.
  ///
  /// What Settings' "Check again" needs and what [start] cannot give it: by the
  /// time anyone reaches Settings the shell has already started the service, so
  /// `start()` takes its idempotent early return and only re-reads the inbox and
  /// re-opens the socket. It never calls `_push.start()` again — which is where
  /// the OS permission is requested and the FCM token fetched. So a customer who
  /// followed the card's own advice, granted notifications in system settings
  /// and came back to press the button was told, correctly and uselessly, that
  /// nothing had changed.
  ///
  /// Returns true when push is working afterwards.
  Future<bool> recheckDelivery() async {
    if (!_auth.isAuthenticated) return false;
    _connect();
    await refresh();
    if (_push.supportedPlatform) {
      await _push.start(onToken: _registerToken);
    }
    notifyListeners();
    return _push.working;
  }

  /// Send a real alert to this account's devices and report what happened.
  ///
  /// The one honest answer to "is my phone getting these?". It goes through the
  /// same push utility every real notification uses, so a pass means the
  /// transport genuinely works rather than that a mock did — and it deliberately
  /// skips the inbox and the socket, because those are the legs that already
  /// work when somebody asks the question.
  Future<String> sendTestAlert() async {
    if (!_auth.isAuthenticated) return 'Sign in first.';
    // Register before testing: a device that has never handed over a token has
    // nothing to send TO, and "no device registered" is the least useful of the
    // possible answers when it is one button press away from being fixed.
    if (_push.supportedPlatform && !_push.working) {
      await _push.start(onToken: _registerToken);
      notifyListeners();
    }
    try {
      final data = await _api.portal('testPush');
      final summary = '${data['summary'] ?? ''}'.trim();
      return summary.isEmpty ? 'Sent.' : summary;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  void _connect() {
    final session = _auth.session;
    if (session == null) return;
    _ws.connect(
      amToken: session.amToken,
      userToken: session.accessToken,
      userName: _auth.user?.userName ?? '',
    );
  }

  Future<void> _registerToken(String token) async {
    try {
      await _api.portal('registerPushToken', params: {
        'token': token,
        'deviceLabel': 'Enersol app',
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {
      // Unreachable server, or a session that just expired. The next start()
      // re-registers; until then the socket still delivers in-app.
    }
  }

  /// Sign-out: close the socket, release the token, empty the list.
  Future<void> stop() async {
    final token = _push.token;
    _ws.disconnect();
    await _push.stop();

    if (token != null && token.isNotEmpty) {
      try {
        await _api.portal('unregisterPushToken', params: {'token': token});
      } catch (_) {
        // Best-effort: a token left behind is deactivated by FCM the first time
        // a send to it comes back unregistered.
      }
    }

    _items = const [];
    _unread = 0;
    _started = false;
    notifyListeners();
  }

  void _onAuthChanged() {
    if (!_auth.isAuthenticated && _started) {
      // Signed out from somewhere else in the app.
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _wsSub?.cancel();
    _pushSub?.cancel();
    _openSub?.cancel();
    _ws.dispose();
    _push.dispose();
    _routes.close();
    super.dispose();
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Re-read the latest page and the unread count.
  Future<void> refresh() async {
    if (!_auth.isAuthenticated) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.portal('notifications');
      _items = ApiClient.asRows(data['notifications'])
          .map(AppNotification.fromJson)
          .toList();
      _unread = (data['unread'] as num?)?.toInt() ?? 0;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your alerts.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Load the page after the ones already held.
  Future<void> loadMore() async {
    final oldest = _items.isEmpty ? null : _items.last.createdAt;
    if (oldest == null) return;
    try {
      final data = await _api.portal(
        'notifications',
        params: {'before': oldest.toIso8601String()},
      );
      final more = ApiClient.asRows(data['notifications'])
          .map(AppNotification.fromJson)
          .toList();
      if (more.isNotEmpty) {
        _items = [..._items, ...more];
        notifyListeners();
      }
    } catch (_) {
      // The button can simply be pressed again.
    }
  }

  Future<void> markRead(String id) => _mark({'ids': [id]}, (n) => n.id == id);

  Future<void> markAllRead() => _mark({'all': true}, (_) => true);

  /// Everything about one record — called when the user OPENS it, which is the
  /// moment the notifications about it stop being news.
  Future<void> markEntityRead(String entity, String entityId) {
    if (entity.isEmpty || entityId.isEmpty) return Future.value();
    return _mark(
      {'entity': entity, 'entityId': entityId},
      (n) => n.entity == entity && n.entityId == entityId,
    );
  }

  // ── Internals ────────────────────────────────────────────────────────────

  /// A row arrived over the socket.
  void _receive(AppNotification row) {
    if (row.id.isEmpty) return;
    // The socket can repeat a row the last refresh already showed.
    if (_items.any((n) => n.id == row.id)) return;
    _items = [row, ..._items];
    if (!row.isRead) _unread++;
    notifyListeners();
    // The app is OPEN — this is the case the socket exists for, and the case
    // where a screen showing "nothing yet" is being read at the very moment the
    // thing it says is missing arrives.
    onNews?.call();
  }

  /// Flip matching rows locally so the UI responds before the round trip, then
  /// let the server's reply set the true count.
  Future<void> _mark(
    Map<String, dynamic> body,
    bool Function(AppNotification) match,
  ) async {
    var cleared = 0;
    _items = _items.map((n) {
      if (n.isRead || !match(n)) return n;
      cleared++;
      return n.copyWith(isRead: true);
    }).toList();
    if (cleared > 0) _unread = (_unread - cleared).clamp(0, 1 << 30);
    notifyListeners();

    try {
      final data = await _api.portal('readNotifications', params: body);
      final server = (data['unread'] as num?)?.toInt();
      if (server != null) {
        _unread = server;
        notifyListeners();
      }
    } catch (_) {
      // The optimistic update stands; the next refresh reconciles it.
    }
  }
}
