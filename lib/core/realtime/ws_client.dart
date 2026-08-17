import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../models/notification.dart';

/// Where the live connection stands, for the small indicator in the header.
enum WsStatus {
  signedOut,
  connecting,
  live,

  /// The server accepted the socket but refused the subscription — almost
  /// always the `ens_notification` WebSocket Event being inactive in API Maker.
  refused,

  /// The handshake tokens were rejected. Retrying the same token is pointless,
  /// so the client waits for a different one.
  rejected,
  retrying,
}

/// The live half of notification delivery, speaking API Maker's WebSocket
/// protocol directly.
///
/// WHY A RAW SOCKET AND NOT JUST FCM. FCM is the OS's business: it is right for
/// a phone with the app closed, and useless for a customer who is *looking at*
/// the Service screen when their request is resolved — Android will not draw a
/// banner for a foreground app and iOS suppresses it too. The socket is what
/// makes the bell light up while the app is open, and it is also the path that
/// keeps working when the device has no Play Services or the user denied
/// notification permission.
///
/// THE PROTOCOL, verbatim from the admin panel's own client:
///   * connect to `wsHost` with the two session tokens as QUERY PARAMETERS —
///     a WebSocket handshake carries no custom headers, and `user-path` has to
///     travel the same way because there is no URL segment to put it in;
///   * the server replies `CONNECTED`, at which point one `REGISTER` frame
///     subscribes to the custom event `ens_notification`;
///   * the subscription criterion is `{ enot_userName_str: <me> }` and must be
///     a SCALAR equal to this user's own name. API Maker matches criteria by
///     exact equality — there is no `$in` — and the server-side guard rejects a
///     subscription for anyone else's username, so this is both how delivery is
///     addressed and how it is secured;
///   * `NOTIFICATION` frames then arrive carrying the row.
class WsClient {
  WsClient();

  static const String _event = 'ens_notification';
  static const Duration _minBackoff = Duration(seconds: 3);
  static const Duration _maxBackoff = Duration(seconds: 60);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Duration _backoff = _minBackoff;

  String _amToken = '';
  String _userToken = '';
  String _userName = '';

  /// A token the server has already said no to. Reconnecting into the identical
  /// rejection every few seconds costs a handshake and changes nothing, so the
  /// client waits for a different one (a refresh, or a fresh sign-in).
  String _rejectedToken = '';
  bool _closedByUs = false;

  final _status = ValueNotifier<WsStatus>(WsStatus.signedOut);

  /// Live connection state, for the header's delivery-health dot.
  ValueListenable<WsStatus> get status => _status;

  final _notifications = StreamController<AppNotification>.broadcast();

  /// Rows that arrived while the app was open.
  Stream<AppNotification> get notifications => _notifications.stream;

  bool get isLive => _status.value == WsStatus.live;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Point the client at a session and connect. Safe to call repeatedly — the
  /// screen that owns the bell calls it on every resume.
  void connect({
    required String amToken,
    required String userToken,
    required String userName,
  }) {
    _amToken = amToken;
    _userToken = userToken;
    _userName = userName;

    if (amToken.isEmpty || userName.isEmpty) {
      _status.value = WsStatus.signedOut;
      return;
    }
    if (amToken == _rejectedToken) {
      _status.value = WsStatus.rejected;
      return;
    }
    if (_channel != null) return; // already up, or coming up

    _closedByUs = false;
    _status.value = WsStatus.connecting;

    final uri = Uri.parse(
      '${Env.wsHost}'
      '?authTokenInfo=enersol_authorization'
      '&user-path=${Uri.encodeComponent(Env.userPath)}'
      '&x-am-authorization=${Uri.encodeComponent(amToken)}'
      '&x-am-user-authorization=${Uri.encodeComponent(userToken)}',
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onFrame,
        onError: (_) => _dropped('The connection failed.'),
        onDone: () => _dropped('The connection dropped.'),
        cancelOnError: true,
      );
    } catch (_) {
      _dropped('The connection could not be opened.');
    }
  }

  /// Close for good (sign-out). A later [connect] starts fresh.
  void disconnect() {
    _closedByUs = true;
    _retry?.cancel();
    _retry = null;
    _backoff = _minBackoff;
    _rejectedToken = '';
    _tearDown();
    _status.value = WsStatus.signedOut;
  }

  void dispose() {
    disconnect();
    _notifications.close();
    _status.dispose();
  }

  // ── Incoming ─────────────────────────────────────────────────────────────

  void _onFrame(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      final parsed = jsonDecode('$raw');
      if (parsed is! Map) return;
      frame = Map<String, dynamic>.from(parsed);
    } catch (_) {
      return;
    }

    final response = frame['response'] is Map
        ? Map<String, dynamic>.from(frame['response'] as Map)
        : const <String, dynamic>{};

    switch ('${frame['type'] ?? ''}') {
      // The handshake failed its own token check, and the server closes right
      // after. Remember which token so the retry loop does not burn on it.
      case 'TOKEN_VALIDATION':
        _rejectedToken = _amToken;
        _status.value = WsStatus.rejected;
        return;

      case 'CONNECTED':
        if (response['connected'] != true) return;
        _backoff = _minBackoff;
        _rejectedToken = '';
        // Still 'connecting': an open socket with no subscription on it
        // delivers nothing, so this is not yet live.
        _status.value = WsStatus.connecting;
        _register();
        return;

      case 'REGISTER':
        final invalid = response['invalidOnEvents'];
        final valid = response['validOnEvents'];
        if (invalid is List && invalid.isNotEmpty) {
          _status.value = WsStatus.refused;
        } else if (valid is List && valid.isNotEmpty) {
          _status.value = WsStatus.live;
        } else {
          _status.value = WsStatus.refused;
        }
        return;

      case 'NOTIFICATION':
        final eventData = response['eventData'];
        final row = eventData is Map ? eventData['notification'] : null;
        if (row is Map) {
          _notifications.add(
            AppNotification.fromJson(Map<String, dynamic>.from(row)),
          );
        }
        return;
    }
  }

  void _register() {
    final channel = _channel;
    if (channel == null || _userName.isEmpty) return;
    channel.sink.add(jsonEncode({
      'objType': 'REGISTER',
      'onEvents': [
        {
          'eventType': 'CUSTOM_WS_EVENTS',
          'apiName': _event,
          // Deliver the whole payload — no `select`, so no field stripping.
          'getEventData': true,
          'condition': {
            'conditionType': 'RESPONSE',
            'criteria': {'enot_userName_str': _userName},
          },
        },
      ],
    }));
  }

  // ── Reconnect ────────────────────────────────────────────────────────────

  void _dropped(String _) {
    _tearDown();
    if (_closedByUs) return;
    // A 'no' from the server is sticky: both refusals are followed by a close,
    // and the generic "retrying" would otherwise bury the only state that says
    // what is actually wrong.
    if (_status.value != WsStatus.refused &&
        _status.value != WsStatus.rejected) {
      _status.value = WsStatus.retrying;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_retry != null || _closedByUs) return;
    final delay = _backoff;
    _backoff = Duration(
      milliseconds: (_backoff.inMilliseconds * 2).clamp(
        _minBackoff.inMilliseconds,
        _maxBackoff.inMilliseconds,
      ),
    );
    _retry = Timer(delay, () {
      _retry = null;
      connect(
        amToken: _amToken,
        userToken: _userToken,
        userName: _userName,
      );
    });
  }

  void _tearDown() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // Already gone.
    }
    _channel = null;
  }
}
