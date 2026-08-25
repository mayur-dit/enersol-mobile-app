import 'dart:convert';

import 'package:enersol_customer/core/api/api_client.dart';
import 'package:enersol_customer/core/data/customer_repository.dart';
import 'package:enersol_customer/core/state/auth_service.dart';
import 'package:enersol_customer/core/state/notification_service.dart';
import 'package:enersol_customer/core/state/shell_controller.dart';
import 'package:enersol_customer/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Shared scaffolding for the app's tests.
///
/// NO MOCKING PACKAGE. Every collaborator here is either substitutable through
/// a constructor (`ApiClient` takes an `http.Client`) or a plain class that can
/// be subclassed, so the suite needs nothing beyond `flutter_test` and the
/// `http` package's own `MockClient`. That keeps `flutter test` runnable on a
/// clean checkout with no extra dependency to keep current.

/// Stops google_fonts reaching the network during a test.
///
/// `AppTheme` builds its text theme from `GoogleFonts.interTextTheme`, which
/// tries to fetch Inter on first use. In a test that surfaces as an HTTP call to
/// a real host and a pile of unrelated failures; disabling runtime fetching
/// makes it fall back to the bundled platform font, which is what an offline
/// phone does anyway.
void useOfflineFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// An [ApiClient] whose every request is answered by [respond].
///
/// [respond] receives the decoded request body, so a test can branch on the
/// portal action being called.
ApiClient fakeApi(http.Response Function(Map<String, dynamic> body) respond) {
  return ApiClient(
    httpClient: MockClient((request) async {
      Map<String, dynamic> body = const {};
      if (request.body.isNotEmpty) {
        try {
          final parsed = jsonDecode(request.body);
          if (parsed is Map) body = Map<String, dynamic>.from(parsed);
        } catch (_) {
          // An upload is multipart, not JSON. A screen that uploads must not
          // blow up in the fake before it reaches what the test is about.
        }
      }
      return respond(body);
    }),
  );
}

/// A 200 carrying API Maker's `{ data: … }` envelope.
http.Response ok(Object? data) => http.Response(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {'content-type': 'application/json'},
    );

/// A failure in API Maker's real error envelope — `errors[].message` is where
/// a custom API's `errorList` strings actually arrive.
http.Response failure(String message, {int status = 500}) => http.Response(
      jsonEncode({
        'success': false,
        'statusCode': status,
        'errors': [
          {'code': 'E_TEST', 'message': message},
        ],
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A repository wired to a fake transport.
CustomerRepository repoWith(
  http.Response Function(Map<String, dynamic> body) respond,
) {
  final api = fakeApi(respond);
  return CustomerRepository(api, AuthService(api));
}

/// Wraps [child] in just enough app to render: theme, providers, directionality.
///
/// `AuthService` is real but never signed in — the screens only read
/// `user?.name` and friends off it to pre-fill a form, and a null session is a
/// legitimate state for them.
///
/// `NotificationService` and `ShellController` are here because every screen
/// built on `PageScaffold` now carries the shell's own header — the bell needs
/// an unread count and the sidebar needs a way back to the tabs. Neither is
/// started: constructing the service only subscribes it to the session, and it
/// opens no socket until `start()` is called, which nothing here does.
Widget harness(Widget child, {CustomerRepository? repository}) {
  final repo = repository ?? repoWith((_) => ok(const {}));
  final api = fakeApi((_) => ok(const {}));
  final auth = AuthService(api);
  return MultiProvider(
    providers: [
      Provider<CustomerRepository>.value(value: repo),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<NotificationService>(
        create: (_) => NotificationService(api, auth),
      ),
      Provider<ShellController>(create: (_) => ShellController()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

/// One entry of the portal's `applications` payload, with sensible defaults so
/// a test names only the field it is about.
Map<String, dynamic> applicationRow({
  String reference = 'RE1007',
  String status = 'Open',
  String stage = 'Site Survey',
  bool isConfirmed = false,
  double capacityKw = 5,
  List<Map<String, dynamic>>? stages,
}) =>
    {
      'reference': reference,
      'status': status,
      'stage': stage,
      'isConfirmed': isConfirmed,
      'capacityKw': capacityKw,
      'projectType': 'Residential',
      'discom': 'MGVCL',
      'siteAddress': 'Alkapuri, Vadodara',
      'submittedOn': '2026-08-01T04:30:00.000Z',
      'stages': stages ??
          [
            {'label': 'New Enquiry', 'state': 'done', 'group': 'Enquiry'},
            {'label': 'Site Survey', 'state': 'current', 'group': 'Enquiry'},
            {'label': 'Proposal', 'state': 'pending', 'group': 'Enquiry'},
          ],
    };

/// One entry of the portal's `documentRequests` payload.
///
/// Defaults describe the ordinary case — one pending request, nothing sent yet
/// — so a test names only the field it is actually about.
Map<String, dynamic> documentRequestRow({
  String id = '68f0000000000000000000d1',
  String title = 'Latest electricity bill',
  String status = 'Pending',
  String stepKey = '',
  String projectId = 'PR1001',
  int minFiles = 0,
  Object? dueDate,
  List<Map<String, dynamic>> files = const [],
}) =>
    {
      'id': id,
      'number': 'DR1001',
      'title': title,
      'description': 'A clear photograph of the whole page.',
      'category': 'DISCOM',
      'projectId': projectId,
      'projectName': 'Patel residence',
      'stepKey': stepKey,
      'stepName': stepKey.isEmpty ? '' : 'Sanction',
      'status': status,
      'priority': 'Normal',
      'mandatory': true,
      'dueDate': dueDate,
      'minFiles': minFiles,
      'reviewNote': '',
      'customerNote': '',
      'files': files,
      'requestedAt': '2026-08-01T04:30:00.000Z',
    };

/// An in-memory stand-in for the phone's secure enclave.
///
/// `AuthService` writes the session, and the biometric vault, through
/// `flutter_secure_storage` — a plugin with no implementation in a test binding,
/// so every call throws `MissingPluginException` and nothing about sign-in can
/// be exercised. Answering its method channel from a plain `Map` is what makes
/// the session lifecycle testable at all.
///
/// Returns the map, so a test can seed it before the service reads it and assert
/// on it afterwards.
Map<String, String> mockSecureStorage([Map<String, String>? initial]) {
  final store = <String, String>{...?initial};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
    final key = '${args['key'] ?? ''}';
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key] = '${args['value'] ?? ''}';
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'containsKey':
        return store.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
      default:
        return null;
    }
  });
  return store;
}

/// A `/login` reply in the shape the backend actually sends.
///
/// Two tokens on `tokenResp` rather than one: API Maker issues the api-user's
/// token and the signed-in user's token side by side, and they travel on
/// different headers.
Map<String, dynamic> loginPayload({
  String userType = 'CUSTOMER',
  String userName = 'ravi',
  List<Map<String, dynamic>>? tokens,
}) =>
    {
      'user': {
        '_id': '68f0000000000000000000aa',
        'ens_name_str': 'Ravi Mehta',
        'ens_userName_str': userName,
        'ens_userType_str': userType,
        'ens_role_str': 'CUSTOMER',
        'ens_referralCode_str': 'RAVI100',
      },
      'tokenResp': tokens ??
          [
            {'token': 'am-token', 'refresh_token': 'am-refresh'},
            {'token': 'user-token', 'refresh_token': 'user-refresh'},
          ],
    };
