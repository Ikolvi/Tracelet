group = "com.ikolvi.tracelet_sync"
version = "3.3.0"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// Support older Flutter apps that do not have AGP's built-in Kotlin enabled
// (AGP < 9, or AGP 9 with `android.builtInKotlin=false` — the Flutter 3.44
// template default). String concatenation bypasses Flutter's regex scanner to
// prevent false warnings in modern Flutter. Under built-in Kotlin AGP provides
// KGP and rejects an explicitly-applied `kotlin-android`, so guard the apply.
val builtInKotlin = if (project.hasProperty("android.builtInKotlin"))
    project.property("android.builtInKotlin").toString().toBoolean() else false
if (!builtInKotlin) {
    apply(plugin = "org.jetbrains.kotlin." + "android")
}

android {
    namespace = "com.ikolvi.tracelet_sync"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// Set the Kotlin bytecode target via `tasks.withType(KotlinCompile)` rather than
// the top-level `kotlin { }` DSL. In a Kotlin-DSL script the `kotlin { }`
// accessor is only generated when KGP is applied through the declarative
// `plugins { }` block; under legacy/`builtInKotlin=false` hosts KGP is applied
// imperatively above, so the accessor is unresolved and the script won't compile.
// `tasks.withType` compiles in both modes.
tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    compileOnly("com.ikolvi:tracelet-sdk:3.8.8")
    implementation("com.ikolvi:tracelet-sync-sdk:3.8.8")
    testImplementation("com.ikolvi:tracelet-sdk:3.5.6")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
