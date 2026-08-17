import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/firebase_options.dart';

/// Handles a push that arrives with the app closed or backgrounded.
///
/// Must be a TOP-LEVEL function: Flutter spins up a separate isolate for it,
/// and only a top-level (or static) entry point can be looked up by name from
/// native code. Nothing here may touch app state — that isolate has none.
///
/// The body is deliberately empty. The backend sends native devices a real
/// `notification` block, so the OS itself draws the banner without the app
/// running; this exists only so `onBackgroundMessage` is registered, which is
/// what makes the tap that follows deliver `getInitialMessage` to us.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// OS-level push, and the banner for a message that arrives while the app is
/// open.
///
/// TWO DELIVERY PATHS, ONE INBOX. FCM is for when the app is not in front of
/// the user; the WebSocket (see `WsClient`) is for when it is. They both end at
/// the same `ens_notifications` rows, so nothing here parses business meaning
/// out of a push — it draws a banner, and the inbox is refreshed from the
/// server, which stays the single source of truth for what the user has.
///
/// EVERY STEP IS OPTIONAL AND SILENT ON FAILURE. Push is a convenience layered
/// on a working app: an unregistered Firebase project, a user who declined the
/// permission prompt, a device with no Play Services — each of those must mean
/// "no banners", never a crash or a blocked sign-in.
class PushService {
  PushService();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    // Must match `android.notification.channel_id` in the backend's FCM
    // payload, or Android 8+ files pushes under a channel with no user-facing
    // setting and the importance chosen here is ignored.
    'enersol_alerts',
    'Enersol alerts',
    description: 'Service updates, documents and application progress.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _token;

  /// Why push could not start at all, when the reason is a missing console step
  /// rather than the user's own permission. Surfaced in Settings so the answer
  /// to "my phone is quiet" is not a support ticket.
  String _setupNote = '';
  String get setupNote => _setupNote;

  /// The FCM registration token for this install, once there is one.
  String? get token => _token;

  /// Whether push is actually working end to end on this device — the health
  /// tick beside the bell.
  bool get working => _ready && (_token?.isNotEmpty ?? false);

  final _opened = StreamController<Map<String, dynamic>>.broadcast();

  /// Payloads of notifications the user TAPPED, so the app can route.
  Stream<Map<String, dynamic>> get opened => _opened.stream;

  final _arrived = StreamController<void>.broadcast();

  /// Fires when a push lands while the app is running, so the inbox re-reads.
  Stream<void> get arrived => _arrived.stream;

  // ── Setup ────────────────────────────────────────────────────────────────

  /// Bring Firebase up and start listening. Returns the token, or null when
  /// push is unavailable for any reason.
  ///
  /// [onToken] is called for the first token AND for every refresh — a token is
  /// rotated by the OS without warning, and a stale one on the server is a
  /// phone that has quietly stopped ringing.
  Future<String?> start({required Future<void> Function(String) onToken}) async {
    if (!DefaultFirebaseOptions.available) {
      // No Firebase app registered for this platform yet. In-app delivery over
      // the WebSocket is unaffected; see firebase_options.dart. Printed rather
      // than swallowed because "the phone is quiet with the app closed" is
      // otherwise indistinguishable from a backend that sent nothing.
      debugPrint('[push] not configured: ${DefaultFirebaseOptions.setupNote}');
      _setupNote = DefaultFirebaseOptions.setupNote;
      return null;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.current,
        );
      }

      final messaging = FirebaseMessaging.instance;

      // iOS and Android 13+ both gate notifications behind a prompt. A refusal
      // is a normal outcome, not an error: the app carries on and the bell
      // still fills over the socket.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _ready = false;
        return null;
      }

      await _initLocal();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      // Foreground: the OS shows nothing for the app in front of the user, by
      // design on both platforms, so the banner is drawn here.
      FirebaseMessaging.onMessage.listen(_onForeground);

      // Tapped while the app was merely backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _opened.add(_dataOf(m)),
      );

      // Tapped while the app was CLOSED — this is the launch itself, and the
      // message is available exactly once.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _opened.add(_dataOf(initial));

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        onToken(t);
      });

      final token = await messaging.getToken();
      _ready = true;
      _token = token;
      if (token != null && token.isNotEmpty) await onToken(token);
      return token;
    } catch (e) {
      // A missing google-services registration, no Play Services, an offline
      // first launch — all of them land here and all of them mean the same
      // thing to the user: no banners, everything else works.
      debugPrint('[push] unavailable: $e');
      _ready = false;
      return null;
    }
  }

  Future<void> _initLocal() async {
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // The OS asks on Firebase's behalf in requestPermission() above; asking
        // twice would show the user two prompts for one decision.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _local.initialize(
      settings: init,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _opened.add({'url': payload});
        }
      },
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  // ── Incoming ─────────────────────────────────────────────────────────────

  Future<void> _onForeground(RemoteMessage message) async {
    _arrived.add(null);

    final data = _dataOf(message);
    final title = '${message.notification?.title ?? data['title'] ?? ''}';
    final body = '${message.notification?.body ?? data['body'] ?? ''}';
    if (title.isEmpty && body.isEmpty) return;

    try {
      await _local.show(
        // A stable-ish id per notification so a repeat about the same record
        // replaces its banner rather than stacking a second one.
        id: '${data['entityId'] ?? message.messageId ?? ''}'.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: '${data['url'] ?? ''}',
      );
    } catch (_) {
      // The inbox already has the row; a missing banner is not worth an error.
    }
  }

  Map<String, dynamic> _dataOf(RemoteMessage m) =>
      m.data.map((k, v) => MapEntry(k, v));

  /// Drop this device's registration (sign-out). The server row is deactivated
  /// by the caller; this stops the OS handing us a token for the next user.
  Future<void> stop() async {
    _ready = false;
    _token = null;
    if (!DefaultFirebaseOptions.available || Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Nothing to delete, or offline — the server row is already inactive.
    }
  }

  void dispose() {
    _opened.close();
    _arrived.close();
  }

  /// iOS needs an APNs token before FCM will issue one; on a simulator there is
  /// never one. Exposed so the settings screen can explain a quiet phone.
  bool get supportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
