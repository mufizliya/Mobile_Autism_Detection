plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.autism_detection_mobile_replica"
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
        applicationId = "com.example.autism_detection_mobile_replica"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {

            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
dependencies {
    val cameraxVersion = "1.4.2"

implementation("androidx.camera:camera-core:$cameraxVersion")
implementation("androidx.camera:camera-camera2:$cameraxVersion")
implementation("androidx.camera:camera-lifecycle:$cameraxVersion")

implementation("com.google.mlkit:face-detection:16.1.7")
implementation("com.google.mediapipe:tasks-vision:0.10.14")
implementation("com.google.guava:guava:33.2.1-android")
}
configurations.configureEach {
    resolutionStrategy.force("com.google.guava:guava:33.2.1-android")
}
flutter {
    source = "../.."
}
