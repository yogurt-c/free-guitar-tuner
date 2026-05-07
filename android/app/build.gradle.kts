plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun decodeDartDefines(): Map<String, String> {
    val raw = (project.findProperty("dart-defines") as? String) ?: return emptyMap()
    return raw.split(",").associate { encoded ->
        val decoded = String(java.util.Base64.getDecoder().decode(encoded))
        val idx = decoded.indexOf('=')
        decoded.substring(0, idx) to decoded.substring(idx + 1)
    }
}

val dartDefines = decodeDartDefines()

android {
    namespace = "com.yogurtc.freetune"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.yogurtc.freetune"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAndroidAppId"] =
            dartDefines["ADMOB_ANDROID_APP_ID"] ?: "ca-app-pub-3940256099942544~3347511713"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
