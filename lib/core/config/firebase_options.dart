import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase project configuration, hand-written rather than generated.
///
/// WHY NOT `flutterfire configure` / google-services.json — the platform files
/// that tool writes are just these same values in another format, and passing
/// them to `Firebase.initializeApp(options:)` keeps the whole configuration in
/// one readable file that a reviewer can compare against the admin panel's
/// `environment.ts`. The two MUST name the same project (`enersol-2f5fe`) or the
/// server, which holds one service-account credential, cannot reach this app.
///
/// NONE OF THIS IS SECRET. An FCM API key and app id identify a client; they
/// authorise nothing. The credential that can actually send a push is the
/// service-account JSON, which lives only in the backend's `common
/// .fcmServiceAccount` secret.
///
/// TO FINISH SETUP: register an Android app (and an iOS app, when that build is
/// wanted) under the same Firebase project and paste the values below. Until
/// then [available] is false, `Firebase.initializeApp` is never called, and the
/// app runs exactly as it does today — WebSocket notifications still arrive
/// in-app, only the OS-level push is missing. This is deliberate: a missing
/// console step must not be a crash on launch.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Shared by every platform of one Firebase project.
  static const String _projectId = 'enersol-2f5fe';
  static const String _messagingSenderId = '137907833728';
  static const String _storageBucket = 'enersol-2f5fe.firebasestorage.app';

  /// Firebase console → Project settings → Your apps → **Android app**, package
  /// name `com.savainfosystems.enersol_customer`.
  ///
  /// THESE MUST BE THE ANDROID APP'S VALUES, not the web app's. The pair below
  /// was copied from the admin panel's `environment.ts`, which registers the
  /// WEB app — the app id says `:web:`, and Firebase Installations refuses to
  /// issue an FCM token to an Android process presenting a web app id. That is
  /// why a closed phone never rang: registration failed on launch, the device
  /// had no token, and the server had nothing to send to. [_androidReady] below
  /// refuses to initialise on a web app id rather than failing again every
  /// launch with an error only `flutter logs` would show.
  static const String _androidAppId = '1:137907833728:web:d6b13b2e43599484b88f65';
  static const String _androidApiKey = 'AIzaSyDp93h6UO_VaR6sSSR0zKx642SkKqix4GY';

  /// The same, for the iOS app.
  static const String _iosAppId = '';
  static const String _iosApiKey = '';
  static const String _iosBundleId = 'com.savainfosystems.enersolCustomer';

  /// Whether this platform has been registered in the console yet.
  static bool get available => _current != null;

  /// The Android app id is an ANDROID one, not a web or iOS app pasted by
  /// mistake. `1:<sender>:android:<hash>` is the shape the console prints, and
  /// the Installations service checks it before it will hand out a token.
  static bool get _androidReady =>
      _androidApiKey.isNotEmpty && _androidAppId.contains(':android:');

  /// Why push is off on this device, for the Settings screen and the logs.
  /// Empty when everything needed is present.
  static String get setupNote {
    // `Platform.isAndroid` throws on the web, where dart:io is only a stub, so
    // this has to answer before any of the reads below.
    if (kIsWeb) {
      return 'Push is not wired up for the web build — no web app is registered '
          'here and no service worker ships with it. Notifications still arrive '
          'in-app over the WebSocket.';
    }
    if (Platform.isAndroid && !_androidReady) {
      return 'Add the Android app (package com.savainfosystems.enersol_customer) '
          'in the Firebase console and paste its App ID + API key into '
          'firebase_options.dart — the values here belong to the web app.';
    }
    if (Platform.isIOS && (_iosAppId.isEmpty || _iosApiKey.isEmpty)) {
      return 'Register the iOS app in the Firebase console and paste its App ID '
          '+ API key into firebase_options.dart.';
    }
    return '';
  }

  static FirebaseOptions? get _current {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      if (!_androidReady) return null;
      return const FirebaseOptions(
        apiKey: _androidApiKey,
        appId: _androidAppId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        storageBucket: _storageBucket,
      );
    }
    if (Platform.isIOS) {
      if (_iosAppId.isEmpty || _iosApiKey.isEmpty) return null;
      return const FirebaseOptions(
        apiKey: _iosApiKey,
        appId: _iosAppId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        storageBucket: _storageBucket,
        iosBundleId: _iosBundleId,
      );
    }
    return null;
  }

  /// Throws when unavailable — callers must check [available] first.
  static FirebaseOptions get current =>
      _current ??
      (throw StateError(
        'This platform has no Firebase app registered under $_projectId yet.',
      ));
}
