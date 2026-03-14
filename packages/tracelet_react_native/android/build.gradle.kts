plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.tracelet.reactnative"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        named("main") {
            java.srcDirs("src/main/kotlin")
            // Shared core engines (framework-agnostic)
            java.srcDirs("../../../../native/android/tracelet-core/src/main/kotlin")
        }
    }
}

dependencies {
    // React Native
    implementation("com.facebook.react:react-android")

    // Play Services Location (FusedLocationProvider, ActivityRecognition, Geofencing)
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Room (SQLite persistence)
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")

    // WorkManager (periodic mode, background scheduling)
    implementation("androidx.work:work-runtime-ktx:2.10.0")

    // OkHttp (HTTP sync)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
