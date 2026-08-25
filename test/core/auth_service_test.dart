import 'dart:convert';

import 'package:enersol_customer/core/api/api_client.dart';
import 'package:enersol_customer/core/state/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The session: who is signed in, and how they get back in tomorrow.
///
/// Two rules carry the whole file. THIS APP IS FOR CUSTOMERS ONLY — the login
/// endpoint is shared with the web admin panel, so a staff or vendor account
/// authenticates perfectly well and would land in an app that has no screens
/// for them. And A CORRUPT STORED SESSION MUST NEVER WEDGE THE LAUNCH: the
/// splash waits on `restore()`, so an exception there is a phone stuck on a
/// logo with no way out but a reinstall.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restore', () {
    test('starts out restoring, so the app shows the splash rather than the login screen', () {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      expect(auth.restoring, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });

    test('brings a returning customer straight back in', () async {
      final session = {
        'user': loginPayload()['user'],
        'amToken': 'am-token',
        'amRefreshToken': 'am-refresh',
        'accessToken': 'user-token',
        'refreshToken': 'user-refresh',
      };
      mockSecureStorage({'enersol_session': jsonEncode(session)});

      final auth = AuthService(fakeApi((_) => ok(const {})));
      await auth.restore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user?.userName, 'ravi');
      expect(auth.session?.amToken, 'am-token');
      expect(auth.restoring, isFalse);
    });

    test('leaves a first-time launch signed out, and lets it past the splash', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      await auth.restore();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.restoring, isFalse);
    });

    test('throws away a corrupt blob instead of wedging the app on the splash', () async {
      final store = mockSecureStorage({'enersol_session': '{not json'});
      final auth = AuthService(fakeApi((_) => ok(const {})));
      await auth.restore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.restoring, isFalse);
      expect(store.containsKey('enersol_session'), isFalse, reason: 'the unreadable blob must be cleared');
    });

    test('ignores a stored value that is not a session at all', () async {
      mockSecureStorage({'enersol_session': '"just a string"'});
      final auth = AuthService(fakeApi((_) => ok(const {})));
      await auth.restore();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.restoring, isFalse);
    });

    test('treats an empty stored value as no session', () async {
      mockSecureStorage({'enersol_session': ''});
      final auth = AuthService(fakeApi((_) => ok(const {})));
      await auth.restore();
      expect(auth.isAuthenticated, isFalse);
    });

    test('repaints once it knows, so the splash is replaced exactly once', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      var notified = 0;
      auth.addListener(() => notified++);
      await auth.restore();
      expect(notified, 1);
    });
  });

  group('login', () {
    test('signs a customer in and persists the session for next launch', () async {
      final store = mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload())));

      await auth.login('ravi', 'secret');

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user?.name, 'Ravi Mehta');
      expect(store['enersol_session'], isNotNull);
      expect(jsonDecode(store['enersol_session']!)['accessToken'], 'user-token');
    });

    test('sends the credentials under the field names the shared endpoint expects', () async {
      mockSecureStorage();
      Map<String, dynamic>? sent;
      final auth = AuthService(fakeApi((body) {
        sent = body;
        return ok(loginPayload());
      }));

      await auth.login('ravi', 'secret');

      expect(sent?['ens_userName_str'], 'ravi');
      expect(sent?['ens_pass_str'], 'secret');
      expect(sent?['ens_appType_str'], 'CUSTOMER');
    });

    test('trims the username, because a phone keyboard adds a trailing space', () async {
      mockSecureStorage();
      Map<String, dynamic>? sent;
      final auth = AuthService(fakeApi((body) {
        sent = body;
        return ok(loginPayload());
      }));

      await auth.login('  ravi  ', 'secret');
      expect(sent?['ens_userName_str'], 'ravi');
    });

    test('does not trim the password — a space in it is a character', () async {
      mockSecureStorage();
      Map<String, dynamic>? sent;
      final auth = AuthService(fakeApi((body) {
        sent = body;
        return ok(loginPayload());
      }));

      await auth.login('ravi', ' secret ');
      expect(sent?['ens_pass_str'], ' secret ');
    });

    test('refuses a staff account, which the shared endpoint would happily authenticate', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userType: 'SYSTEM_USER'))));

      await expectLater(
        auth.login('ravi', 'secret'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('customers only'))),
      );
      expect(auth.isAuthenticated, isFalse);
    });

    test('refuses a vendor account for the same reason', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userType: 'VENDOR'))));
      await expectLater(auth.login('v', 'secret'), throwsA(isA<ApiException>()));
      expect(auth.isAuthenticated, isFalse);
    });

    test('stores nothing when the account is refused', () async {
      final store = mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userType: 'SYSTEM_USER'))));
      await auth.login('ravi', 'secret').catchError((_) {});
      expect(store.containsKey('enersol_session'), isFalse);
    });

    test('complains clearly when the reply carries no profile', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {'tokenResp': []})));
      await expectLater(
        auth.login('ravi', 'secret'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('no profile'))),
      );
    });

    test('complains clearly when the reply is not the envelope it expects', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok('yes')));
      await expectLater(
        auth.login('ravi', 'secret'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Unexpected reply'))),
      );
    });

    test('surfaces the server\'s own sentence rather than a status code', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => failure('Your account is not approved yet.', status: 401)));
      await expectLater(
        auth.login('ravi', 'secret'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Your account is not approved yet.')),
      );
    });

    test('keeps the two tokens apart — they travel on different headers', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload())));
      await auth.login('ravi', 'secret');
      expect(auth.session?.amToken, 'am-token');
      expect(auth.session?.accessToken, 'user-token');
      expect(auth.session?.refreshToken, 'user-refresh');
    });

    test('falls back to the single token when only one is issued', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload(tokens: [
            {'token': 'only-token', 'refresh_token': 'only-refresh'},
          ]))));

      await auth.login('ravi', 'secret');
      expect(auth.session?.amToken, 'only-token');
      expect(auth.session?.accessToken, 'only-token');
    });

    test('signs in even when no token is issued at all, rather than throwing', () async {
      // The session is still the record of who is signed in; an empty token is
      // a 401 on the next call, which the app already handles.
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload(tokens: const []))));
      await auth.login('ravi', 'secret');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.session?.amToken, '');
    });

    test('arms the biometric vault only for the account it was set up for', () async {
      // Enabling biometrics always arms it for whoever is signed in at that
      // moment, so a plain password sign-in as somebody else must not silently
      // overwrite a different account's saved entry.
      final store = mockSecureStorage({
        'enersol_bio_user': 'someone-else',
        'enersol_bio_session': '{"stale":true}',
      });
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userName: 'ravi'))));

      await auth.login('ravi', 'secret');
      expect(store['enersol_bio_session'], '{"stale":true}');
      expect(store['enersol_bio_user'], 'someone-else');
    });

    test('refreshes the vault when the same account signs in with a password', () async {
      final store = mockSecureStorage({
        'enersol_bio_user': 'ravi',
        'enersol_bio_session': '{"stale":true}',
      });
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userName: 'ravi'))));

      await auth.login('ravi', 'secret');
      expect(store['enersol_bio_session'], isNot('{"stale":true}'));
      expect(jsonDecode(store['enersol_bio_session']!)['accessToken'], 'user-token');
    });

    test('repaints once the session is in place', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload())));
      var notified = 0;
      auth.addListener(() => notified++);
      await auth.login('ravi', 'secret');
      expect(notified, 1);
    });
  });

  group('logout', () {
    test('clears the session and the stored blob', () async {
      final store = mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload())));
      await auth.login('ravi', 'secret');

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
      expect(store.containsKey('enersol_session'), isFalse);
    });

    test('leaves the biometric vault armed, so the next unlock still works', () async {
      final store = mockSecureStorage({'enersol_bio_user': 'ravi'});
      final auth = AuthService(fakeApi((_) => ok(loginPayload(userName: 'ravi'))));
      await auth.login('ravi', 'secret');
      await auth.logout();

      expect(store.containsKey('enersol_bio_session'), isTrue);
      expect(store['enersol_bio_user'], 'ravi');
    });

    test('signs out even when the audit call fails — nothing may block it', () async {
      mockSecureStorage();
      var calls = 0;
      final auth = AuthService(fakeApi((body) {
        calls++;
        return calls == 1 ? ok(loginPayload()) : failure('activity log is down');
      }));
      await auth.login('ravi', 'secret');

      await auth.logout();
      expect(auth.isAuthenticated, isFalse);
    });

    test('repaints so the shell is replaced by the login screen', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(loginPayload())));
      await auth.login('ravi', 'secret');

      var notified = 0;
      auth.addListener(() => notified++);
      await auth.logout();
      expect(notified, 1);
    });
  });

  group('biometric enrolment', () {
    test('reports not enrolled when nothing has been sealed away', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      expect(await auth.biometricEnrolled(), isFalse);
    });

    test('reports enrolled once a vault exists', () async {
      mockSecureStorage({'enersol_bio_session': '{"user":{}}'});
      final auth = AuthService(fakeApi((_) => ok(const {})));
      expect(await auth.biometricEnrolled(), isTrue);
    });

    test('treats an empty vault as not enrolled', () async {
      mockSecureStorage({'enersol_bio_session': ''});
      final auth = AuthService(fakeApi((_) => ok(const {})));
      expect(await auth.biometricEnrolled(), isFalse);
    });

    test('cannot be armed while signed out — there is no session to seal', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      expect(await auth.enableBiometric(), isFalse);
    });

    test('forgets both halves of the vault when it is turned off', () async {
      final store = mockSecureStorage({
        'enersol_bio_session': '{"user":{}}',
        'enersol_bio_user': 'ravi',
      });
      final auth = AuthService(fakeApi((_) => ok(const {})));

      await auth.disableBiometric();
      expect(store.containsKey('enersol_bio_session'), isFalse);
      expect(store.containsKey('enersol_bio_user'), isFalse);
    });

    test('refuses to unlock when nothing was ever sealed', () async {
      mockSecureStorage();
      final auth = AuthService(fakeApi((_) => ok(const {})));
      await expectLater(
        auth.loginWithBiometric(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('not set up'))),
      );
    });
  });
}
