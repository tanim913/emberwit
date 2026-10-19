import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The upload key lives outside the repository, by default in
// ~/.emberwit-release/key.properties (override with EMBERWIT_SIGNING=/path).
// Without it, release builds fall back to the debug key so CI and fresh clones
// can still build. Store uploads always come from the real key.
val signingFile = file(
    System.getenv("EMBERWIT_SIGNING")
        ?: "${System.getProperty("user.home")}/.emberwit-release/key.properties",
)
val signing = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}

android {
    namespace = "app.emberwit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.emberwit"
        // API 26 (Android 8.0): needed for the platform APIs used by the
        // device profiler and for a modern TLS stack.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // arm64-v8a for real phones, x86_64 for emulators. 32-bit ARM is
            // not supported: on-device LLM inference is not viable there.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // One dimension, three environments. Names must match AppFlavor in
    // lib/core/config/flavor_config.dart.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appName"] = "Emberwit Dev"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".stg"
            versionNameSuffix = "-stg"
            manifestPlaceholders["appName"] = "Emberwit Staging"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appName"] = "Emberwit"
        }
    }

    signingConfigs {
        if (signing.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    androidResources {
        // Keep the bundled benchmark model uncompressed in the APK so it can
        // be streamed out with a known size (and copied only once).
        noCompress += "gguf"
    }

    packaging {
        jniLibs {
            // Extract native libraries to the filesystem so llama.cpp can
            // discover its CPU backend modules (one per ARM feature level)
            // with a directory scan and dlopen the best one.
            useLegacyPackaging = true
            // 64-bit only. Some plugins ship 32-bit prebuilts; packaging
            // them would let 32-bit phones install an app that cannot run.
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Theme.AppCompat for the biometric prompt (local_auth) on Android 8.
    implementation("androidx.appcompat:appcompat:1.7.1")
}
