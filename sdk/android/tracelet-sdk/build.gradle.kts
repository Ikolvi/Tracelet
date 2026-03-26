plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
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

    kotlinOptions {
        jvmTarget = "17"
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
}

dependencies {
    // Play Services Location (FusedLocationProvider, ActivityRecognition, Geofencing)
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // WorkManager for reliable background scheduling
    implementation("androidx.work:work-runtime-ktx:2.11.1")

    // OkHttp for HTTP sync
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("com.squareup.okhttp3:okhttp-tls:5.3.2")

    // SQLCipher for database encryption (Enterprise)
    implementation("net.zetetic:sqlcipher-android:4.6.1@aar")
    implementation("androidx.sqlite:sqlite:2.6.2")

    // EncryptedSharedPreferences for key management (Enterprise)
    implementation("androidx.security:security-crypto:1.1.0")

    // Play Integrity for device attestation (Enterprise)
    implementation("com.google.android.play:integrity:1.6.0")

    // Core KTX
    implementation("androidx.core:core-ktx:1.18.0")

    // Lifecycle
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.lifecycle:lifecycle-service:2.10.0")

    // JSON
    implementation("org.json:json:20251224")

    // Testing
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.23.0")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito.kotlin:mockito-kotlin:6.3.0")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("androidx.work:work-testing:2.11.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
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
                    description.set("Production-grade background geolocation SDK for Android")
                    url.set("https://github.com/Ikolvi/Tracelet")

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

        // Repository is managed by io.github.gradle-nexus.publish-plugin in root build.gradle.kts.
        // Use: ./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository
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
