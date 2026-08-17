package com.savainfosystems.enersol_customer

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth —
// the biometric prompt is a fragment and cannot attach otherwise.
class MainActivity : FlutterFragmentActivity()
