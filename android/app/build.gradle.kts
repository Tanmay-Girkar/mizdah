plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mizdah.mizdah"
    // Compile against the latest SDK we have available so we can use
    // newer Android APIs that are gated by version checks at runtime,
    // but TARGET an older SDK so the OS doesn't apply the very newest
    // strict-mode behaviours to us. See `targetSdk` below.
    compileSdk = 36
    // Bumped to satisfy speech_to_text 7.x which requires NDK 28.x.
    // NDKs are backward-compatible, so existing native deps
    // (flutter_webrtc, mediasoup_client_flutter) keep working.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mizdah.mizdah"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Pin targetSdk at 34 (Android 14). Android 15 (35) and 16
        // (36) tightened the rules around `mediaProjection`-typed
        // foreground services: the FGS can ONLY start AFTER the
        // user has granted the MediaProjection consent dialog. The
        // current screen-share flow starts the FGS BEFORE calling
        // `getDisplayMedia` (which IS what triggers the consent
        // dialog), and inverting the order isn't possible because
        // flutter_webrtc 0.12.7 needs the FGS already running by
        // the time it consumes the projection token. So with
        // targetSdk=36 the screen-share flow crashes with:
        //   SecurityException: Starting FGS with type
        //   mediaProjection ... requires either CAPTURE_VIDEO_OUTPUT
        //   or android:project_media (the projection appop, set
        //   only AFTER consent).
        // Targeting SDK 34 keeps the looser pre-Android-15 rules
        // and the existing flow works on every Android 14+ device.
        // Play Store policy as of 2026-05 still accepts targetSdk
        // 34 for updates, so this is a clean retreat. Bump again
        // when flutter_webrtc ships a 0.14+ that handles the
        // consent-first ordering itself.
        targetSdk = 34
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

flutter {
    source = "../.."
}
