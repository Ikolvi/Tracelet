plugins {
    id("com.android.library") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.10" apply false
    id("io.github.gradle-nexus.publish-plugin") version "2.0.0"
}

nexusPublishing {
    packageGroup.set("com.ikolvi")
    repositories {
        sonatype {
            // Central Portal staging API (OSSRH legacy was sunset June 2025)
            nexusUrl.set(uri("https://ossrh-staging-api.central.sonatype.com/service/local/"))
            snapshotRepositoryUrl.set(uri("https://central.sonatype.com/repository/maven-snapshots/"))
            username.set(findProperty("ossrhUsername") as? String ?: System.getenv("OSSRH_USERNAME"))
            password.set(findProperty("ossrhPassword") as? String ?: System.getenv("OSSRH_PASSWORD"))
        }
    }
}
