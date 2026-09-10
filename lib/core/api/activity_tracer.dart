import 'dart:convert';

/// What one traced call was, for the activity log.
///
/// Built by `ApiClient` at the call site and handed to the tracer once the
/// response (or failure) is known — the mobile counterpart of the admin panel's
/// HTTP interceptor.
class ActivityContext {
  const ActivityContext({
    required this.action,
    required this.opType,
    this.module = 'Customer App',
    this.table,
    this.recordId,
    this.method = 'POST',
    this.endpoint,
    this.payload,
  });

  final String action;

  /// CREATE | UPDATE | DELETE | CUSTOM — an API Maker tracing header, not a
  /// column: `ens_activity_logs` records the verb in `eact_action_str`.
  final String opType;
  final String module;
  final String? table;
  final String? recordId;
  final String method;
  final String? endpoint;
  final Map<String, dynamic>? payload;
}

/// Keys whose values never leave the device, at any depth.
final RegExp _secretKey = RegExp(
  r'(pass|password|pwd|secret|token|otp|authorization|apikey|api_key|credential|signature|refresh)',
  caseSensitive: false,
);

/// Per-blob character cap. The server clips again at 16000.
const int _maxBlobChars = 8000;

/// Deep copy with secrets removed and bulk lists clipped.
///
/// The activity log stores whole request and response bodies, which is the
/// point — but a login body or a token-carrying response must not be among
/// them.
dynamic redact(dynamic value, [int depth = 0]) {
  if (value == null) return null;
  if (depth > 8) return '[deep]';
  if (value is List) {
    final head = value.take(50).map((v) => redact(v, depth + 1)).toList();
    if (value.length > 50) head.add('…+${value.length - 50} more');
    return head;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, val) {
      final k = '$key';
      out[k] = _secretKey.hasMatch(k) ? '[redacted]' : redact(val, depth + 1);
    });
    return out;
  }
  if (value is String && value.length > _maxBlobChars) {
    return '${value.substring(0, _maxBlobChars)}…[truncated]';
  }
  if (value is num || value is bool || value is String) return value;
  return '$value';
}

/// One activity-log entry, in the shape `/log-activity` accepts.
Map<String, dynamic> buildActivityEntry({
  required ActivityContext context,
  required bool success,
  required int durationMs,
  int? status,
  Map<String, dynamic>? output,
  String? error,
  String? sessionId,
  String? userId,
  String? userName,
  String? name,
  String? role,
}) {
  return {
    'action': context.action,
    'opType': context.opType,
    'module': context.module,
    if (context.table != null) 'table': context.table,
    if (context.recordId != null) 'recordId': context.recordId,
    'method': context.method,
    if (context.endpoint != null) 'endpoint': context.endpoint,
    'status': status,
    'success': success,
    'durationMs': durationMs,
    if (context.payload != null) 'payload': redact(context.payload),
    if (output != null) 'output': redact(output),
    'error': ?error,
    'message': success ? context.action : 'Failed: ${error ?? 'unknown error'}',
    'source': 'mobile',
    'sessionId': ?sessionId,
    'userId': ?userId,
    'user': ?userName,
    'userName': ?name,
    'role': ?role,
    // Exact time the operation completed, captured here rather than on arrival
    // so a slow or retried log request cannot skew it.
    'at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Encode an entry batch as the `/log-activity` request body.
String encodeActivityBatch(List<Map<String, dynamic>> entries) =>
    jsonEncode({'entries': entries});
