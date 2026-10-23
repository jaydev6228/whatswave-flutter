import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing credentials live outside the repository, in a file git ignores.
// Absent on CI and on any machine that has not been given the key, which is
// why the release build type falls back to debug signing below rather than
// failing the build -- a contributor should still be able to run a release
// build locally, they just cannot produce an uploadable one.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.tsjaydevra.whatswave"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tsjaydevra.whatswave"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug keys produce a bundle Play rejects. The fallback exists so
            // a machine without the key can still build; it must never be what
            // ships, which is why the release build logs which one it used.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A warning here is useless: Flutter filters Gradle's log output, so a
// `logger.warn` about debug signing never reaches the terminal. Fail instead,
// and only for the bundle -- `assembleRelease` stays available for local
// release testing, while `bundleRelease`, the artifact Play actually accepts,
// cannot be produced with debug keys at all.
tasks.whenTaskAdded {
    if (name == "bundleRelease" && !hasUploadKey) {
        doFirst {
            throw GradleException(
                "Refusing to build a release bundle with debug keys.\n\n" +
                    "android/key.properties is missing. Copy " +
                    "android/key.properties.example, point storeFile at your " +
                    "upload keystore, and fill in the passwords.\n\n" +
                    "Play rejects debug-signed bundles, so this would fail at " +
                    "upload anyway -- failing here is just faster.",
            )
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
