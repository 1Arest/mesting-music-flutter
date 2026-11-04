import java.util.Base64
import java.util.Properties
import java.security.MessageDigest
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter forwards dart-defines as a Gradle input, including when it reuses a
// daemon. Derive the sandbox identity from the same flag the test asserts.
val benchmarkDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',').filter { it.isNotBlank() }.mapNotNull {
        runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull()
    }
val benchmarkBuild = benchmarkDefines.contains("MESTING_ISOLATED_BENCHMARK=true")

android {
    namespace = "com.mesting.music"
    compileSdk = flutter.compileSdkVersion
    // integration_test currently requires this newer NDK. Pinning it here
    // keeps local and CI Release builds on the same compatible toolchain.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mesting.music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Explicit, profile-only sandbox. Release entry points cannot inherit
        // a benchmark identity or renderer override from a forgotten env var.
        val sandbox = benchmarkBuild
        if (sandbox && gradle.startParameter.taskNames.none { it.contains("Profile", ignoreCase = true) }) {
            throw GradleException("mestingBenchmark is allowed only for profile builds")
        }
        resValue("string", "mesting_benchmark_backend", if (sandbox)
            benchmarkDefines.firstOrNull { it.startsWith("MESTING_BENCHMARK_BACKEND=") }
                ?.substringAfter('=') ?: "auto" else "auto")
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("stable") {
            dimension = "distribution"
        }
        create("javaMysqlTest") {
            dimension = "distribution"
            applicationIdSuffix = ".javatest"
        }
        // Keep the integration sandbox installable beside both existing apps.
        // Native md3Music libraries live in src/beta, never in stable/main.
        create("beta") {
            dimension = "distribution"
            applicationIdSuffix = if (benchmarkBuild)
                ".beta.benchmark" else ".beta"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.add("lib/x86_64/**")
    }
}

flutter {
    source = "../.."
}

// The upstream 3.41.9 Release engine ignores explicit OpenGLES selection. Use
// our pinned, narrowly patched native libraries only in betaRelease. Keeping
// the official Java embedding preserves plugin compatibility, and other
// flavors/build modes keep their existing upstream engine dependencies.
val recoveryEngineDirectory = rootProject.file("../third_party/flutter_engine/android-release")
val recoveryEngineJars = listOf("arm64-v8a-release.jar", "armeabi-v7a-release.jar")
android.sourceSets.maybeCreate("betaRelease").assets.srcDir(recoveryEngineDirectory.resolve("assets"))
configurations.configureEach {
    if (name.startsWith("betaRelease")) {
        exclude(group = "io.flutter", module = "arm64_v8a_release")
        exclude(group = "io.flutter", module = "armeabi_v7a_release")
        // Public releases already exclude x86_64 in packaging above; do not
        // resolve an unused upstream engine beside the two verified ARM jars.
        exclude(group = "io.flutter", module = "x86_64_release")
    }
}
dependencies {
    add("betaReleaseImplementation", files(recoveryEngineJars.map { recoveryEngineDirectory.resolve(it) }))
    // audio_service already supplies media 1.7.0 at runtime through its
    // implementation dependency. Our narrow foreground bridge also needs the
    // superclass and MediaStyle on the app's compile classpath; do not add a
    // second runtime library or upgrade the pinned playback dependency.
    compileOnly("androidx.media:media:1.7.0")
}
tasks.withType<JavaCompile>().configureEach {
    // The existing music notification's room text is stored as UTF-8 source,
    // independent of the Windows build machine's default code page.
    options.encoding = "UTF-8"
}
val verifyRecoveryEngine = tasks.register("verifyMestingReleaseEngine") {
    // Execute on each release build so a stale SDK, missing binary or changed
    // file fails before packaging rather than silently restoring Vulkan.
    doLast {
        val manifestFile = recoveryEngineDirectory.resolve("engine-manifest.json")
        check(manifestFile.isFile) { "Build/export the pinned Release engine first; see third_party/flutter_engine/README.md" }
        val manifest = JsonSlurper().parse(manifestFile) as Map<*, *>
        val expectedRevision = "42d3d75a56efe1a2e9902f52dc8006099c45d937"
        check(manifest["runtimeMode"] == "release" && manifest["upstreamEngineRevision"] == expectedRevision)
        val properties = Properties().apply {
            rootProject.file("local.properties").inputStream().use { load(it) }
        }
        val sdkStamp = file("${properties.getProperty("flutter.sdk")}/bin/cache/engine.stamp")
        check(sdkStamp.readText().trim() == expectedRevision) { "Flutter SDK differs from the pinned native Release engine" }
        fun digest(file: java.io.File) = MessageDigest.getInstance("SHA-256")
            .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        val patch = rootProject.file("../third_party/flutter_engine/release-opengles.patch")
        check(digest(patch) == manifest["patchSha256"]) { "Rebuild the engine after changing its patch" }
        val entries = manifest["files"] as List<*>
        check(entries.size == 2 && entries.map { (it as Map<*, *>)["jar"] }.toSet() == recoveryEngineJars.toSet())
        entries.forEach { value ->
            val item = value as Map<*, *>
            val jar = recoveryEngineDirectory.resolve(item["jar"] as String)
            check(jar.isFile && digest(jar) == item["jarSha256"]) { "Release engine missing or checksum mismatch: ${jar.name}" }
        }
        val license = recoveryEngineDirectory.resolve("assets/LICENSE.flutter-engine.txt")
        check(license.isFile && digest(license) == manifest["licensesSha256"]) { "Keep the complete engine license payload" }
    }
}
tasks.matching { it.name == "preBetaReleaseBuild" }.configureEach {
    dependsOn(verifyRecoveryEngine)
}
