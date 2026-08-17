import 'dart:convert';

import 'package:enersol_customer/core/api/api_client.dart';
import 'package:enersol_customer/core/data/customer_repository.dart';
import 'package:enersol_customer/core/state/auth_service.dart';
import 'package:enersol_customer/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
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
        final parsed = jsonDecode(request.body);
        if (parsed is Map) body = Map<String, dynamic>.from(parsed);
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
Widget harness(Widget child, {CustomerRepository? repository}) {
  final repo = repository ?? repoWith((_) => ok(const {}));
  return MultiProvider(
    providers: [
      Provider<CustomerRepository>.value(value: repo),
      ChangeNotifierProvider<AuthService>(
        create: (_) => AuthService(fakeApi((_) => ok(const {}))),
      ),
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
