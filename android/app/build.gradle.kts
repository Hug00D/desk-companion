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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
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
    // 定義 CameraX 版本
    val camerax_version = "1.3.0"

    // CameraX 核心庫
    implementation("androidx.camera:camera-core:${camerax_version}")
    implementation("androidx.camera:camera-camera2:${camerax_version}")

    // CameraX 生命週期庫（讓相機隨 Activity 自動開啟/關閉）
    implementation("androidx.camera:camera-lifecycle:${camerax_version}")

    // CameraX 視圖庫（提供 PreviewView 方便顯示畫面）
    implementation("androidx.camera:camera-view:${camerax_version}")

    // Step 1: 先將人臉 / EAR 偵測從 ML Kit Face Detection 替換為 MediaPipe Face Landmarker。
    implementation("com.google.mediapipe:tasks-vision:0.10.33")

    // Pose Detector：暫時保留原本肩膀/坐姿邏輯，下一步再替換成 MediaPipe Pose Landmarker。
    implementation("com.google.mlkit:pose-detection:18.0.0-beta3")
}
