import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// The sentence to show a customer for a failed load.
///
/// Every screen used to pass `'${snap.error}'` straight into `ErrorRetry`. For
/// an [ApiException] that happens to read well — its `toString` is the server's
/// own message — but for anything else it prints Dart's default, and a customer
/// on a roof was shown `type 'Null' is not a subtype of type 'String'`. One
/// place decides what leaves the app, so a new failure mode cannot leak an
/// implementation detail by being caught somewhere that forgot to translate it.
String friendlyError(Object? error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error == null) return fallback;
  if (error is ApiException) {
    final message = error.message.trim();
    return message.isEmpty ? fallback : message;
  }
  // Anything that is NOT an ApiException never reached the network — the client
  // wraps every transport failure itself. The customer still gets the fallback
  // sentence, but the real cause is logged so a device-only fault (a plugin
  // channel, secure storage) is diagnosable from a release build.
  debugPrint('Unhandled ${error.runtimeType}: $error');
  return fallback;
}
