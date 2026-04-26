plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.wktk"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.wktk"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        // 시그널링 서버 주소 (Render 무료 호스팅, 영구 고정 URL).
        buildConfigField("String", "SIGNALING_URL", "\"https://wktk-signaling.onrender.com\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            buildConfigField("String", "SIGNALING_URL", "\"https://wktk-signaling.onrender.com\"")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    // APK 출력 이름: wktk-debug.apk / wktk-release.apk (기본 'app-' 접두사 제거).
    setProperty("archivesBaseName", "wktk")
}

dependencies {
    // Compose
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.animation:animation")        // animateColorAsState 등
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.5")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.1")

    // Socket.IO 클라이언트
    implementation("io.socket:socket.io-client:2.1.1") {
        exclude(group = "org.json", module = "json")
    }

    // WebRTC: GetStream 미러 (Google의 google-webrtc는 단종)
    implementation("io.getstream:stream-webrtc-android:1.1.3")
}
