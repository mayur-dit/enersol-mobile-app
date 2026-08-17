import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'activity_tracer.dart';

/// Raised for any non-2xx reply, carrying the server's message when it sent one.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin wrapper over the API Maker HTTP surface.
///
/// Two token headers travel on every authenticated call, matching the admin
/// panel's interceptor:
///   `x-am-authorization`      — the api-user token (what may be called)
///   `x-am-user-authorization` — the per-user token (who is calling)
class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  String? _amToken;
  String? _userToken;

  /// The signed-in user's id, sent with portal calls as the identity fallback
  /// for platform versions where the server can't read it from the token.
  String? _userId;

  /// Actor details stamped onto activity entries. The server overrides the
  /// identity from the token where it can, so these are a labelling aid, not a
  /// claim the log has to trust.
  String? _userName;
  String? _name;
  String? _role;

  /// Correlation id for this app run, so one session reads as one story.
  ///
  /// The bound stays at 1 << 30: on the web `<<` is JavaScript's 32-bit shift,
  /// where `1 << 32` wraps to 0 and `nextInt` then throws.
  final String _sessionId =
      's_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_'
      '${Random().nextInt(1 << 30).toRadixString(36)}';

  void setTokens({String? amToken, String? userToken}) {
    _amToken = amToken;
    _userToken = userToken;
  }

  void setUserId(String? id) => _userId = id;

  /// Label activity rows with who is acting.
  void setActor({String? userName, String? name, String? role}) {
    _userName = userName;
    _name = name;
    _role = role;
  }

  void clearTokens() {
    _amToken = null;
    _userToken = null;
    _userId = null;
    _userName = null;
    _name = null;
    _role = null;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_amToken != null && _amToken!.isNotEmpty)
          'x-am-authorization': _amToken!,
        if (_userToken != null && _userToken!.isNotEmpty)
          'x-am-user-authorization': _userToken!,
      };

  static const Duration _timeout = Duration(seconds: 30);

  // ── Activity tracing ─────────────────────────────────────────────────────

  /// Endpoints that are never traced from the client.
  ///
  /// The auth flows run without a session, so a client-stamped row would have
  /// no actor — and each is already logged server-side with the real user id.
  /// `log-activity` is here because tracing the tracer recurses.
  static const Set<String> _untracedApis = {
    'log-activity',
    'login',
    'forgot-password',
    'reset-password',
  };

  /// Portal actions that only read. Anything else is assumed to change
  /// something and is traced — so a portal action added later is audited by
  /// default rather than by remembering to opt in.
  static const Set<String> _readOnlyPortalActions = {
    'applications',
    'documents',
    'serviceRequests',
    'referrals',
    'generation',
    'discoms',
    'notifications',
    // Listing what the office is waiting on. `submitDocumentRequest` is
    // deliberately NOT here — sending a document is a write, and this is the
    // one thing a customer does that somebody may later need to prove.
    'documentRequests',
    // A diagnostic the customer ran on their own phone, about their own phone.
    // It writes nothing and reads nothing of theirs.
    'testPush',
  };

  // ── Custom APIs ──────────────────────────────────────────────────────────

  /// POST `/api/custom-api/{userPath}/{path}`.
  ///
  /// Traced automatically unless the path is in [_untracedApis]. Callers that
  /// know more about the call (the portal, below) pass their own [activity]
  /// context; everything else gets a generic one derived from the path, which
  /// is what keeps a future endpoint audited without touching this file.
  Future<Map<String, dynamic>> customApi(
    String path, {
    Map<String, dynamic>? body,
    ActivityContext? activity,
    bool trace = true,
  }) async {
    final uri =
        Uri.parse('${Env.apiHost}/api/custom-api/${Env.userPath}/$path');
    final endpoint = '/api/custom-api/${Env.userPath}/$path';
    final context = !trace || _untracedApis.contains(path)
        ? null
        : activity ??
            ActivityContext(
              action: _humanise(path),
              opType: 'CUSTOM',
              method: 'POST',
              endpoint: endpoint,
              payload: body,
            );

    return _send(
      () => _http.post(
        uri,
        headers: _headers,
        body: jsonEncode(body ?? const {}),
      ),
      activity: context,
    );
  }

  /// Upload one file to OneDrive through `Enersol Upload`.
  ///
  /// The SAME endpoint the two web apps use, rather than a portal action that
  /// takes bytes: one uploader means one set of file-type rules, one
  /// storage-accounting path and one place a size limit is enforced. The
  /// customer group was granted this API for exactly this screen.
  ///
  /// Returns the proxy URLs the caller then posts to the portal — the bytes and
  /// the business record are deliberately two steps, so a half-finished upload
  /// never leaves a document request pointing at nothing.
  Future<Map<String, dynamic>> uploadFile(
    File file, {
    String folder = 'customer-uploads',
    String? fileName,
  }) async {
    final uri =
        Uri.parse('${Env.apiHost}/api/custom-api/${Env.userPath}/upload');
    final request = http.MultipartRequest('POST', uri)
      // NOT `_headers`: setting Content-Type here would clobber the multipart
      // boundary the client generates, and the server would read an empty body.
      ..headers.addAll({
        if (_amToken != null && _amToken!.isNotEmpty)
          'x-am-authorization': _amToken!,
        if (_userToken != null && _userToken!.isNotEmpty)
          'x-am-user-authorization': _userToken!,
      })
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath(
        'files',
        file.path,
        filename: fileName,
      ));

    // A generous ceiling, separate from [_timeout]: a 30-second cap is right for
    // a JSON round trip and wrong for a photograph on a rural connection, which
    // is exactly where this screen gets used.
    final streamed = await request.send().timeout(const Duration(minutes: 10));
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(res.body);
      body = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      body = {};
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        _messageFrom(body) ?? 'Upload failed (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }

    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  /// "create-lead" -> "Create Lead".
  static String _humanise(String raw) => raw
      .split(RegExp(r'[-_/]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// One action of the customer portal, returning its `data` payload.
  ///
  /// The portal is the app's only data door — it scopes every read to the
  /// signed-in customer server-side (see `Enersol Customer Portal`). API Maker
  /// wraps a custom API's return value under `data`, which is unwrapped here.
  Future<Map<String, dynamic>> portal(
    String action, {
    Map<String, dynamic>? params,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      // Identity fallback — the server prefers the token, but falls back to
      // this when the token's decoded shape differs by platform version.
      if (_userId != null && _userId!.isNotEmpty) 'userId': _userId,
      ...?params,
    };
    // A portal read is not worth an audit row; a portal write always is.
    final isRead = _readOnlyPortalActions.contains(action);
    final res = await customApi(
      'customer-portal',
      body: body,
      trace: !isRead,
      activity: ActivityContext(
        action: _humanise(action),
        opType: 'CUSTOM',
        endpoint: '/api/custom-api/${Env.userPath}/customer-portal',
        payload: body,
      ),
    );
    final data = res['data'];
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  /// A list field from a portal response, normalised to maps.
  static List<Map<String, dynamic>> asRows(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  // ── Schema CRUD ──────────────────────────────────────────────────────────

  /// POST `/api/schema/{collection}/query` — the generic read used app-wide.
  Future<List<Map<String, dynamic>>> query(
    String collection, {
    Map<String, dynamic>? find,
    Map<String, dynamic>? sort,
    Map<String, dynamic>? select,
    int? limit,
    int? skip,
  }) async {
    final uri = Uri.parse('${Env.apiHost}/api/schema/$collection/query');
    final res = await _send(() => _http.post(
          uri,
          headers: _headers,
          body: jsonEncode({
            'find': ?find,
            'sort': ?sort,
            'select': ?select,
            'limit': ?limit,
            'skip': ?skip,
          }),
        ));

    final data = res['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// POST `/api/schema/{collection}/save-single-or-multiple`.
  Future<Map<String, dynamic>> save(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse(
      '${Env.apiHost}/api/schema/$collection/save-single-or-multiple',
    );
    final id = data['_id'];
    final res = await _send(
      () => _http.post(
        uri,
        headers: _headers,
        body: jsonEncode(data),
      ),
      activity: ActivityContext(
        action: '${id == null ? 'Create' : 'Update'} ${_humanise(collection.replaceFirst('ens_', ''))}',
        opType: id == null ? 'CREATE' : 'UPDATE',
        table: collection,
        recordId: id?.toString(),
        endpoint: '/api/schema/$collection/save-single-or-multiple',
        payload: data,
      ),
    );
    final payload = res['data'];
    if (payload is Map) return Map<String, dynamic>.from(payload);
    if (payload is List && payload.isNotEmpty && payload.first is Map) {
      return Map<String, dynamic>.from(payload.first as Map);
    }
    return res;
  }

  /// PUT `/api/schema/{collection}/update-by-id/{id}`.
  Future<Map<String, dynamic>> updateById(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse(
      '${Env.apiHost}/api/schema/$collection/update-by-id/$id',
    );
    return _send(
      () => _http.put(
        uri,
        headers: _headers,
        body: jsonEncode(data),
      ),
      activity: ActivityContext(
        action: 'Update ${_humanise(collection.replaceFirst('ens_', ''))}',
        opType: 'UPDATE',
        table: collection,
        recordId: id,
        method: 'PUT',
        endpoint: '/api/schema/$collection/update-by-id/$id',
        payload: data,
      ),
    );
  }

  // ── Transport ────────────────────────────────────────────────────────────

  /// Every call funnels through here, which is why the activity trace lives
  /// here too: one place sees the request, the response, the failure and the
  /// elapsed time, so tracing cannot drift away from what actually happened.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    ActivityContext? activity,
  }) async {
    final started = DateTime.now();
    late final http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      _trace(activity, started, success: false, error: 'Request timed out');
      throw ApiException('The server took too long to respond. Try again.');
    } catch (_) {
      _trace(activity, started, success: false, error: 'Cannot reach the server');
      throw ApiException('Cannot reach the server. Check your connection.');
    }

    Map<String, dynamic> decoded = const {};
    if (res.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(res.body);
        if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
      } catch (_) {
        // Non-JSON body — fall through to the status-code check below.
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _trace(activity, started,
          success: true, status: res.statusCode, output: decoded);
      return decoded;
    }

    final message =
        _messageFrom(decoded) ?? 'Request failed (${res.statusCode}).';
    // A rejected attempt is as much a fact about the user as a successful one.
    _trace(activity, started,
        success: false, status: res.statusCode, error: message);
    throw ApiException(message, statusCode: res.statusCode);
  }

  /// Queue-free by design: a phone can be backgrounded or killed between two
  /// taps, so an entry held back to be batched is an entry likely lost. The app
  /// makes few writes, so one small request each is the cheaper trade.
  void _trace(
    ActivityContext? activity,
    DateTime started, {
    required bool success,
    int? status,
    Map<String, dynamic>? output,
    String? error,
  }) {
    if (activity == null) return;
    // No session means no actor and a guaranteed 401 — nothing worth sending.
    if (_amToken == null || _amToken!.isEmpty) return;

    final entry = buildActivityEntry(
      context: activity,
      success: success,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      status: status,
      output: output,
      error: error,
      sessionId: _sessionId,
      userId: _userId,
      userName: _userName,
      name: _name,
      role: _role,
    );
    unawaited(_postActivity(entry));
  }

  /// Log something the transport cannot observe — a sign-out, a share, any
  /// action that never becomes an HTTP call of its own.
  ///
  /// Awaits the write, unlike the automatic trace, so a caller that is about to
  /// tear the session down can be sure the row was attempted first.
  Future<void> logActivity({
    required String action,
    required String opType,
    String module = 'Customer App',
    String? message,
    Map<String, dynamic>? output,
  }) async {
    if (_amToken == null || _amToken!.isEmpty) return;
    final entry = buildActivityEntry(
      context: ActivityContext(action: action, opType: opType, module: module),
      success: true,
      durationMs: 0,
      output: output,
      sessionId: _sessionId,
      userId: _userId,
      userName: _userName,
      name: _name,
      role: _role,
    );
    if (message != null) entry['message'] = message;
    await _postActivity(entry);
  }

  /// Fire-and-forget POST to `/log-activity`. Deliberately bypasses
  /// [customApi] so it is never itself traced, and swallows every failure —
  /// an audit row must never surface as an error to the person being audited.
  Future<void> _postActivity(Map<String, dynamic> entry) async {
    try {
      await _http
          .post(
            Uri.parse(
              '${Env.apiHost}/api/custom-api/${Env.userPath}/log-activity',
            ),
            headers: _headers,
            body: encodeActivityBatch([entry]),
          )
          .timeout(_timeout);
    } catch (_) {
      // Ignored on purpose.
    }
  }

  /// API Maker reports failures in a few shapes; pick whichever is present.
  ///
  /// `errors[]` FIRST, and it is the one that actually arrives. API Maker's
  /// envelope is `{ success, statusCode, errors: [{ code, message }] }`, and
  /// those messages are the strings listed in a custom API's `errorList` — i.e.
  /// they are written for users. Missing that key was why the app rendered
  /// "Request failed (500)." over a perfectly good sentence explaining what to
  /// do: a customer pressing Send on a service request was told the server had
  /// broken, when the server had politely explained itself.
  String? _messageFrom(Map<String, dynamic> body) {
    final message = _firstMessage(body['errors']) ?? _firstMessage(body['error']);
    if (message != null) return message;

    final plain = body['message'];
    if (plain is String && plain.trim().isNotEmpty) return plain.trim();
    return null;
  }

  /// The first readable string in whatever shape an error field arrived as.
  static String? _firstMessage(dynamic value) {
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    if (value is Map) {
      final m = value['message'];
      return m is String && m.trim().isNotEmpty ? m.trim() : null;
    }
    if (value is List) {
      for (final entry in value) {
        final found = _firstMessage(entry);
        if (found != null) return found;
      }
    }
    return null;
  }
}
