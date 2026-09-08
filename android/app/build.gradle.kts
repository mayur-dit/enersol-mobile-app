plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Must come after the Android plugin. Processes app/google-services.json.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.savainfosystems.enersol_customer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which is what draws an FCM
        // message as a real notification while the app is in the foreground.
        // Without it the build fails outright at :app:checkDebugAarMetadata —
        // it is not an optimisation, it is the dependency's entry price.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // MUST equal `client_info.android_client_info.package_name` in
        // app/google-services.json (`com.enersol.system`) — that pairing is
        // what Firebase Installations checks before it will issue an FCM
        // token, and the google-services plugin fails the build outright if
        // the two disagree. The Kotlin `namespace` above is only the R/
        // BuildConfig package and is deliberately left alone, so MainActivity
        // and the manifest's `.MainActivity` shorthand still resolve.
        applicationId = "com.enersol.system"
        // flutter_secure_storage's encryptedSharedPreferences and local_auth's
        // biometric prompt both need API 23+; Flutter's own floor (24) clears it.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Ships the desugared java.time/java.util backports the notifications
    // plugin schedules against, so they work on the API 24 floor above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
