plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
    id("com.vanniktech.maven.publish.base") version "0.30.0"
}

group = "com.ikolvi"
version = findProperty("SDK_VERSION") as? String ?: "0.1.0"

android {
    namespace = "com.ikolvi.tracelet.sdk"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }

    testOptions {
        unitTests.all {
            val rustDir = project.rootDir.parentFile.resolve("rust-core/target/debug")
            it.systemProperty("jna.library.path", rustDir.absolutePath)
        }
    }
}

dependencies {
    // JNA for Uniffi Rust bindings
    implementation("net.java.dev.jna:jna:5.18.1@aar")

    // Play Services Location (FusedLocationProvider, ActivityRecognition, Geofencing)
    // compileOnly: not bundled in the AAR. Apps that need GMS must add
    // implementation("com.google.android.gms:play-services-location:21.3.0") to their build.gradle.
    compileOnly("com.google.android.gms:play-services-location:21.3.0")

    // Version floor for Play Services Location (see issue #263).
    //
    // Tracelet's compiled bytecode targets the interface-based
    // FusedLocationProviderClient and ActivityRecognitionClient APIs. These
    // types became interfaces in play-services-location 21.x; in older releases
    // (e.g. 19.0.0) they are concrete classes, so calling into them throws
    // java.lang.IncompatibleClassChangeError at runtime.
    //
    // We keep the dependency compileOnly so the SDK still degrades gracefully to
    // the AOSP LocationManager when the host app omits GMS entirely. This
    // constraint does NOT add the dependency to the graph — it only raises the
    // resolved version to a compatible floor (>= 21.2.0) whenever the host app
    // pulls play-services-location in directly or transitively. The constraint is
    // published in the Gradle module metadata (.module) and POM.
    constraints {
        implementation("com.google.android.gms:play-services-location:21.2.0") {
            because(
                "Tracelet uses the interface-based FusedLocationProviderClient/" +
                    "ActivityRecognitionClient APIs (play-services-location >= 21.2.0); " +
                    "older versions expose them as concrete classes and crash with " +
                    "IncompatibleClassChangeError (issue #263)."
            )
        }
    }

    // WorkManager for reliable background scheduling
    implementation("androidx.work:work-runtime-ktx:2.11.1")




    // Play Integrity for device attestation (Enterprise, optional)
    // compileOnly: not bundled in the AAR. Apps that need attestation must add
    // implementation("com.google.android.play:integrity:1.6.0") to their build.gradle.
    compileOnly("com.google.android.play:integrity:1.6.0")

    // Core KTX
    implementation("androidx.core:core-ktx:1.18.0")

    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-service:2.10.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")

    testImplementation("org.json:json:20251224")

    // Testing
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.23.0")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito.kotlin:mockito-kotlin:6.3.0")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("androidx.work:work-testing:2.11.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")

    // Optional deps needed for tests (security-crypto for EncryptionManager tests,
    // play-integrity for DeviceAttestor tests). SQLCipher is intentionally NOT
    // included so SqlCipherMigratorTest can verify the "unavailable" code path.
    testImplementation("androidx.security:security-crypto:1.1.0")
    testImplementation("com.google.android.play:integrity:1.6.0")

    // JNA JAR for running local JVM tests on Mac/Linux/Windows
    testImplementation("net.java.dev.jna:jna:5.18.1")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = "com.ikolvi"
                artifactId = "tracelet-sdk"
                version = project.version.toString()

                pom {
                    name.set("Tracelet SDK")
                    description.set("Production-grade background geolocation SDK for Android. " +
                        "Battery-conscious background geolocation with motion detection, " +
                        "geofencing, SQLite persistence, HTTP sync, and headless execution. " +
                        "See the full documentation at https://github.com/Ikolvi/Tracelet/tree/main/sdk/android")
                    url.set("https://github.com/Ikolvi/Tracelet/tree/main/sdk/android")

                    licenses {
                        license {
                            name.set("Apache License 2.0")
                            url.set("https://www.apache.org/licenses/LICENSE-2.0")
                        }
                    }

                    developers {
                        developer {
                            id.set("ikolvi")
                            name.set("Ikolvi")
                            url.set("https://ikolvi.com")
                        }
                    }

                    scm {
                        url.set("https://github.com/Ikolvi/Tracelet")
                        connection.set("scm:git:git://github.com/Ikolvi/Tracelet.git")
                        developerConnection.set("scm:git:ssh://github.com/Ikolvi/Tracelet.git")
                    }
                }
            }
        }

        // Use vanniktech for actual upload to Central Portal
        // Run: ./gradlew publishAndReleaseToMavenCentral
    }

    mavenPublishing {
        publishToMavenCentral(com.vanniktech.maven.publish.SonatypeHost.CENTRAL_PORTAL, automaticRelease = true)
    }

    signing {
        val signingKey = findProperty("signing.key") as? String ?: System.getenv("SIGNING_KEY")
        val signingPassword = findProperty("signing.password") as? String ?: System.getenv("SIGNING_PASSWORD")
        if (signingKey != null && signingPassword != null) {
            useInMemoryPgpKeys(signingKey, signingPassword)
            sign(publishing.publications["release"])
        }
    }
}
