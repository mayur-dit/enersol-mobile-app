import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../api/api_client.dart';
import '../config/env.dart';
import '../models/user.dart';

/// The biometric the current device offers, for labelling the UI.
///
/// Face unlock exists on both platforms, so face is offered everywhere — only
/// the wording differs: Apple's registered mark "Face ID" on iOS, the generic
/// "Face Unlock" on Android.
enum BiometricKind {
  face,
  fingerprint,
  none;

  String get label => switch (this) {
        BiometricKind.face => Platform.isIOS ? 'Face ID' : 'Face Unlock',
        BiometricKind.fingerprint => 'Fingerprint',
        BiometricKind.none => 'Biometrics',
      };
}

/// Session, credentials and biometric unlock.
///
/// Only a CUSTOMER may sign in here. The login endpoint is shared with the web
/// admin panel, so a staff or vendor account would otherwise authenticate
/// successfully — [login] rejects those explicitly rather than letting someone
/// into an app that has no screens for them.
class AuthService extends ChangeNotifier {
  AuthService(this._api);

  final ApiClient _api;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kSession = 'enersol_session';
  static const _kBioUser = 'enersol_bio_user';
  static const _kBioSession = 'enersol_bio_session';

  final LocalAuthentication _localAuth = LocalAuthentication();

  Session? _session;
  Session? get session => _session;
  AppUser? get user => _session?.user;
  bool get isAuthenticated => _session != null;

  bool _restoring = true;
  bool get restoring => _restoring;

  // ── Startup ──────────────────────────────────────────────────────────────

  /// Reads any persisted session so a returning user lands straight on Home.
  Future<void> restore() async {
    try {
      final raw = await _storage.read(key: _kSession);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _adopt(Session.fromJson(Map<String, dynamic>.from(decoded)));
        }
      }
    } catch (_) {
      // A corrupt blob must never wedge the app on the splash screen.
      await _storage.delete(key: _kSession);
      _session = null;
    }
    _restoring = false;
    notifyListeners();
  }

  /// Point the transport at this session and remember who is acting.
  ///
  /// The one place [_session] and [ApiClient]'s tokens are set together, so
  /// [restore], [login] and [loginWithBiometric] cannot drift into disagreeing
  /// about who is signed in.
  void _adopt(Session session) {
    _session = session;
    _api.setTokens(amToken: session.amToken, userToken: session.accessToken);
    _api.setUserId(session.user.id);
    _api.setActor(
      userName: session.user.userName,
      name: session.user.name,
      role: session.user.role,
    );
  }

  // ── Login ────────────────────────────────────────────────────────────────

  Future<void> login(String userName, String password) async {
    final res = await _api.customApi('login', body: {
      'ens_userName_str': userName.trim(),
      'ens_pass_str': password,
      'ens_appType_str': 'CUSTOMER',
    });

    final data = res['data'];
    if (data is! Map) {
      throw ApiException('Unexpected reply from the server.');
    }
    final map = Map<String, dynamic>.from(data);

    final userJson = map['user'];
    if (userJson is! Map) {
      throw ApiException('Sign-in succeeded but no profile was returned.');
    }
    final appUser = AppUser.fromJson(Map<String, dynamic>.from(userJson));

    if (appUser.userType != Env.allowedUserType) {
      throw ApiException(
        'This app is for customers only. '
        'Please use the Enersol web panel to sign in.',
      );
    }

    // tokenResp is [AM, AM_DB]; fall back to [0] when only one is issued.
    final tokens = (map['tokenResp'] is List)
        ? List<dynamic>.from(map['tokenResp'] as List)
        : const [];
    Map<String, dynamic>? entry(int i) {
      if (i >= tokens.length) return null;
      final t = tokens[i];
      return t is Map ? Map<String, dynamic>.from(t) : null;
    }

    final am = entry(0);
    final usr = entry(1) ?? am;

    final built = Session(
      user: appUser,
      amToken: '${am?['token'] ?? ''}',
      amRefreshToken: '${am?['refresh_token'] ?? ''}',
      accessToken: '${usr?['token'] ?? ''}',
      refreshToken: '${usr?['refresh_token'] ?? ''}',
    );

    _adopt(built);
    await _storage.write(key: _kSession, value: jsonEncode(built.toJson()));

    // Keep an armed biometric vault fresh. It is scoped to a username rather
    // than "biometric is on" because enabling it always arms it for whoever is
    // signed in AT THAT MOMENT (see enableBiometric) — a plain password
    // sign-in as someone else must not silently overwrite a different
    // account's saved fingerprint entry.
    final bioUser = await _storage.read(key: _kBioUser);
    if (bioUser == built.user.userName) {
      await _writeBiometricVault(built);
    }

    notifyListeners();
  }

  Future<void> logout() async {
    // Record the sign-out while the token is still set — clearing it first
    // would leave the call unauthenticated and the row unwritten. The API
    // client swallows any failure, so this cannot block signing out.
    await _api.logActivity(
      action: 'LOGOUT',
      opType: 'LOGOUT',
      module: 'Auth',
      message: 'Signed out',
    );
    _session = null;
    _api.clearTokens();
    await _storage.delete(key: _kSession);
    notifyListeners();
  }

  // ── Biometric unlock ─────────────────────────────────────────────────────

  /// True when the device can perform biometric/local auth.
  ///
  /// Deliberately lenient: `getAvailableBiometrics()` is unreliable across
  /// devices — it returns an empty list on some Androids even with a fingerprint
  /// enrolled, and on iOS before the first prompt. Requiring it to be non-empty
  /// (the old behaviour) is exactly what hid the option. Here it is enough that
  /// the platform reports it can check biometrics OR the device supports secure
  /// auth; the real `authenticate()` prompt handles a missing enrolment with a
  /// clear message rather than the button silently vanishing.
  Future<bool> biometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  /// What the device offers, so the UI can say "Face ID" / "Face Unlock" or
  /// "Fingerprint". Android usually reports face unlock as `strong`/`weak`
  /// rather than `face`, so an explicit face enrolment wins; otherwise we fall
  /// back to Fingerprint, the far more common Android biometric.
  Future<BiometricKind> biometricKind() async {
    try {
      final kinds = await _localAuth.getAvailableBiometrics();
      if (kinds.contains(BiometricType.face)) return BiometricKind.face;
      if (kinds.contains(BiometricType.fingerprint)) {
        return BiometricKind.fingerprint;
      }
      // strong/weak or empty — assume fingerprint on Android, face on iOS,
      // rather than the vague "Biometrics".
      if (kinds.contains(BiometricType.strong) ||
          kinds.contains(BiometricType.weak) ||
          kinds.isEmpty) {
        return Platform.isIOS ? BiometricKind.face : BiometricKind.fingerprint;
      }
      return BiometricKind.none;
    } catch (_) {
      return BiometricKind.none;
    }
  }

  /// True once the user has opted in AND a session is stored for it.
  Future<bool> biometricEnrolled() async {
    final raw = await _storage.read(key: _kBioSession);
    return raw?.isNotEmpty ?? false;
  }

  /// Arms fingerprint sign-in for the CURRENT session on THIS device.
  ///
  /// Requires a successful biometric prompt first, so a bystander holding an
  /// unlocked phone cannot silently arm it. Must be called while signed in —
  /// there is no other session to seal away.
  ///
  /// WHAT IS STORED IS THE SESSION'S TOKENS, NOT THE PASSWORD. An earlier
  /// version of this kept the raw password behind the OS lock so it could be
  /// replayed through the ordinary login call — convenient, but it meant a
  /// compromised device (or a compromised secure-storage implementation on
  /// some OEM Android build) handed over a credential the customer likely
  /// reuses elsewhere, not just access to this app. Tokens are scoped to
  /// Enersol and can be revoked server-side without touching the account
  /// password at all.
  Future<bool> enableBiometric() async {
    final session = _session;
    if (session == null) return false;
    final ok = await _prompt('Confirm to enable biometric sign-in');
    if (!ok) return false;
    await _writeBiometricVault(session);
    notifyListeners();
    return true;
  }

  Future<void> _writeBiometricVault(Session session) async {
    await _storage.write(key: _kBioSession, value: jsonEncode(session.toJson()));
    await _storage.write(key: _kBioUser, value: session.user.userName);
  }

  Future<void> disableBiometric() async {
    await _storage.delete(key: _kBioSession);
    await _storage.delete(key: _kBioUser);
    notifyListeners();
  }

  /// Prompts, then adopts the session sealed by [enableBiometric] directly —
  /// no network round trip, and nothing is ever replayed to the login
  /// endpoint. If the vault cannot be read (an older build's format, or one
  /// tampered with) it is cleared so the next attempt asks for a password
  /// rather than failing the same way forever.
  Future<void> loginWithBiometric() async {
    final raw = await _storage.read(key: _kBioSession);
    if (raw == null || raw.isEmpty) {
      throw ApiException('Biometric sign-in is not set up on this device.');
    }
    final ok = await _prompt('Sign in to Enersol');
    if (!ok) throw ApiException('Biometric not recognised.');

    late final Session restored;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('vault is not a session');
      restored = Session.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      await disableBiometric();
      throw ApiException('Your saved sign-in could not be opened. Please use your password.');
    }

    _adopt(restored);
    await _storage.write(key: _kSession, value: jsonEncode(restored.toJson()));
    notifyListeners();
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // NOT biometric-only. On Android a great many devices expose Face
          // Unlock or the fingerprint sensor as a *weak* (Class 2) biometric,
          // and `biometricOnly: true` refuses those outright — the prompt never
          // appears, enrolment silently fails, credentials are never stored,
          // and so the sign-in option never shows on this platform. Allowing
          // the device credential (PIN/pattern/passcode) as a fallback lets the
          // prompt succeed everywhere; the secret is still gated behind the
          // device's own lock, which is the security property we actually want.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
