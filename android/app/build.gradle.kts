plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.zic.remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications schedules with java.time APIs on old
        // Androids — core library desugaring back-ports them.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dev.zic.remote"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 8.0 (API 26). Flutter's default is 24; 26 is the floor
        // so notification channels exist and cleartext-off covers the
        // oldest supported release.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Plugin AARs ship other ABIs without libflutter.so. A 32-bit phone
        // would install that set and crash, so the release keeps arm64 only.
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        jniLibs {
            excludes += listOf(
                "lib/armeabi/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    // The published app is signed with the debug keystore. CI sets
    // ZIC_KEYSTORE to that same file so an update installs over it.
    // A keystore generated on the runner would not.
    val ciKeystore = System.getenv("ZIC_KEYSTORE")
    if (!ciKeystore.isNullOrBlank()) {
        signingConfigs {
            create("ciRelease") {
                storeFile = file(ciKeystore)
                storePassword = System.getenv("ZIC_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ZIC_KEY_ALIAS")
                keyPassword = System.getenv("ZIC_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (!ciKeystore.isNullOrBlank()) {
                signingConfigs.getByName("ciRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
