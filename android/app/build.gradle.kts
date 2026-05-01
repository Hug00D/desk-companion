plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.desk_companion"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.desk_companion"
        // MediaPipe Tasks Vision requires Android SDK 24 or higher.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

dependencies {
    val cameraxVersion = "1.3.0"

    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // Step 2: 用 MediaPipe Face Landmarker 取代 ML Kit Face Detection，產生臉部 landmarks 並計算 EAR。
    // 這個版本相對穩定；若 Gradle 顯示找不到版本，再依照本機 Maven 可用版本調整。
    implementation("com.google.mediapipe:tasks-vision:0.10.14")

    // Pose Detector 暫時保留 ML Kit，下一步再替換成 MediaPipe Pose Landmarker。
    implementation("com.google.mlkit:pose-detection:18.0.0-beta3")
}
