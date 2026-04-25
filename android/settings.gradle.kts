pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // GetStream WebRTC pre-built (Google의 google-webrtc는 더 이상 게시되지 않음)
        maven("https://jitpack.io")
    }
}

rootProject.name = "wktk"
include(":app")
