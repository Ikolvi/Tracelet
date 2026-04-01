pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.10" apply false
}

// Composite build: resolve tracelet-sdk from local module during development.
// In production, end-user apps get it transitively via Maven Central.
includeBuild("../../sdk/android") {
    dependencySubstitution {
        substitute(module("com.ikolvi:tracelet-sdk")).using(project(":tracelet-sdk"))
    }
}

include(":app")
