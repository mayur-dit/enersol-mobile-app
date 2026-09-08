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
/// Both the Android and the iOS app are registered now (2026-08-27), and the
/// values below are the console's own — cross-check them against
/// `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`,
/// which carry the identical pairs for the native SDKs. If a platform is ever
/// unregistered again, [available] goes false, `Firebase.initializeApp` is
/// never called, and the app runs on the WebSocket alone rather than crashing
/// on launch — a missing console step must not be a crash.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// Shared by every platform of one Firebase project.
  static const String _projectId = 'enersol-2f5fe';
  static const String _messagingSenderId = '137907833728';
  static const String _storageBucket = 'enersol-2f5fe.firebasestorage.app';

  /// Firebase console → Project settings → Your apps → **Android app**, package
  /// name `com.enersol.system` — which is why `applicationId` in
  /// `android/app/build.gradle.kts` says that and not the old
  /// `com.savainfosystems.enersol_customer`. Installations checks the app id
  /// against the package the process actually runs as.
  ///
  /// THESE MUST BE THE ANDROID APP'S VALUES, not the web app's. What used to
  /// sit here was the pair from the admin panel's `environment.ts`, which
  /// registers the WEB app — the app id said `:web:`, and Firebase
  /// Installations refuses to issue an FCM token to an Android process
  /// presenting a web app id. That is why a closed phone never rang:
  /// registration failed on launch, the device had no token, and the server had
  /// nothing to send to. [_androidReady] below still refuses to initialise on a
  /// web app id, so the mistake cannot come back silently.
  static const String _androidAppId =
      '1:137907833728:android:a7f8459b09246a95b88f65';
  static const String _androidApiKey = 'AIzaSyAg91-9s7psEBnDnhdFfhP7BpgoAEOog7Q';

  /// The same, for the iOS app. The API key is a DIFFERENT one from Android's —
  /// the console issues a key per platform, and they are not interchangeable.
  static const String _iosAppId = '1:137907833728:ios:0d7368585ab7120eb88f65';
  static const String _iosApiKey = 'AIzaSyDjH3kafSHe19ry5KA6HUUQAjrcRnSGSCc';
  static const String _iosBundleId = 'com.enersol.system';

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
      return 'Add the Android app (package com.enersol.system) in the Firebase '
          'console and paste its App ID + API key into firebase_options.dart — '
          'the values here belong to the web app.';
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
