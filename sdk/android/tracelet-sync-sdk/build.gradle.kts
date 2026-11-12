plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
    id("signing")
    id("com.vanniktech.maven.publish.base") version "0.37.0"
}

group = "com.ikolvi"
version = findProperty("SDK_VERSION") as? String ?: "0.1.0"

android {
    namespace = "com.ikolvi.tracelet.sdk.sync"
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
        }
    }
}

val emptyJavadocJar by tasks.registering(Jar::class) {
    archiveClassifier.set("javadoc")
    // Empty jar to satisfy Maven Central requirements without triggering Dokka ASM crash
}

dependencies {
    // JNA for Uniffi Rust bindings
    implementation("net.java.dev.jna:jna:5.18.1@aar")
    
    // Kotlin Coroutines for async sync
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    
    // Core SDK
    implementation(project(":tracelet-sdk"))
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                artifact(emptyJavadocJar)
                groupId = "com.ikolvi"
                artifactId = "tracelet-sync-sdk"
                version = project.version.toString()

                pom {
                    name.set("Tracelet Sync SDK")
                    description.set("HTTP Synchronization module for Tracelet SDK on Android. " +
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
    }

    mavenPublishing {
        publishToMavenCentral(automaticRelease = true)
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
