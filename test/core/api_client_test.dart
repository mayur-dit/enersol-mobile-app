import 'dart:convert';

import 'package:enersol_customer/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers.dart';

/// The transport's one job on a failure: find the sentence the server wrote.
///
/// This is the regression suite for a real, user-visible bug — the app rendered
/// "Request failed (500)." over a perfectly good explanation, because it read
/// `error` and `message` but not `errors[]`, which is the key API Maker actually
/// uses for a custom API's declared errorList.
void main() {
  group('ApiClient error messages', () {
    Future<String> messageFor(http.Response response) async {
      final api = fakeApi((_) => response);
      try {
        await api.portal('applications');
        fail('expected the call to throw');
      } on ApiException catch (e) {
        return e.message;
      }
    }

    test('reads API Maker\'s errors[] envelope', () async {
      expect(
        await messageFor(failure('Please describe the problem before sending.')),
        'Please describe the problem before sending.',
      );
    });

    test('falls back to a plain error string', () async {
      final res = http.Response(jsonEncode({'error': 'Not signed in'}), 401);
      expect(await messageFor(res), 'Not signed in');
    });

    test('falls back to an error object', () async {
      final res = http.Response(
        jsonEncode({
          'error': {'message': 'Session expired'},
        }),
        401,
      );
      expect(await messageFor(res), 'Session expired');
    });

    test('falls back to a top-level message', () async {
      final res = http.Response(jsonEncode({'message': 'Unknown action'}), 400);
      expect(await messageFor(res), 'Unknown action');
    });

    test('reports the status code when the body explains nothing', () async {
      final res = http.Response('<html>gateway</html>', 502);
      expect(await messageFor(res), contains('502'));
    });

    test('skips a blank errors[] entry and keeps looking', () async {
      final res = http.Response(
        jsonEncode({
          'errors': [
            {'code': 'E1'},
            {'code': 'E2', 'message': 'The real reason'},
          ],
        }),
        500,
      );
      expect(await messageFor(res), 'The real reason');
    });
  });

  group('ApiClient portal', () {
    test('unwraps the data envelope', () async {
      final api = fakeApi((_) => ok({'applications': []}));
      final data = await api.portal('applications');
      expect(data, containsPair('applications', isEmpty));
    });

    test('sends the action in the body', () async {
      String? seen;
      final api = fakeApi((body) {
        seen = '${body['action']}';
        return ok(const {});
      });
      await api.portal('serviceRequests');
      expect(seen, 'serviceRequests');
    });

    test('passes params through alongside the action', () async {
      Map<String, dynamic>? seen;
      final api = fakeApi((body) {
        seen = body;
        return ok(const {});
      });
      await api.portal('documents', params: {'group': 'warranty'});
      expect(seen?['action'], 'documents');
      expect(seen?['group'], 'warranty');
    });

    test('returns an empty map when data is not an object', () async {
      final api = fakeApi((_) => ok('nope'));
      expect(await api.portal('applications'), isEmpty);
    });
  });

  group('ApiClient.asRows', () {
    test('keeps map entries and drops the rest', () {
      final rows = ApiClient.asRows([
        {'a': 1},
        'junk',
        {'b': 2},
      ]);
      expect(rows, hasLength(2));
      expect(rows.first['a'], 1);
    });

    test('is empty for a non-list', () {
      expect(ApiClient.asRows(null), isEmpty);
      expect(ApiClient.asRows('x'), isEmpty);
    });
  });
}
