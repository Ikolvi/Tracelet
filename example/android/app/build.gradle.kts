plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ikolvi.tracelet.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which the example uses to
        // surface geofence crossings while the app is terminated (#356). Any
        // host app adopting that pattern needs this too.
        isCoreLibraryDesugaringEnabled = true
    }



    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ikolvi.tracelet.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        resources {
            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Google Play Services Location (FusedLocationProvider, ActivityRecognition, Geofencing)
    // Required for high-accuracy tracking and better battery efficiency.
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Database encryption is now handled natively via Rust AES-GCM.
    // SQLCipher is no longer required, saving ~16MB in universal APK size.

    // Device attestation (Play Integrity) — adds ~1MB
    implementation("com.google.android.play:integrity:1.6.0")

    // Backs isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
