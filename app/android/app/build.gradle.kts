import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val androidAbis = providers.environmentVariable("SKYPORT_ANDROID_ABIS")
    .orElse("arm64-v8a").get().split(',').map(String::trim)
val signingPath = providers.environmentVariable("SKYPORT_ANDROID_KEY_PROPERTIES")
    .orElse("${System.getProperty("user.home")}/.config/skyport/android/key.properties")
val signingProperties = Properties().apply {
    val propertiesFile = rootProject.file(signingPath.get())
    if (propertiesFile.isFile) propertiesFile.inputStream().use(::load)
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all(signingProperties::containsKey)

android {
    namespace = "dev.skyport.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.skyport.app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += androidAbis }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("localRelease") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("localRelease")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("com.github.mik3y:usb-serial-for-android:3.11.0")
}

val buildAndroidRust by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile.parentFile)
    commandLine("bash", "scripts/build_android_native.sh")
    environment("SKYPORT_ANDROID_ABIS", androidAbis.joinToString(","))
    environment("SKYPORT_ANDROID_NDK_VERSION", flutter.ndkVersion)
    environment("ANDROID_NDK_HOME", androidComponents.sdkComponents.ndkDirectory.get().asFile.absolutePath)
}

val requireReleaseSigning by tasks.registering {
    doLast {
        check(hasReleaseSigning) {
            "Release signing required; run scripts/android_release.sh init-signing or set SKYPORT_ANDROID_KEY_PROPERTIES"
        }
    }
}

tasks.configureEach {
    if (name.endsWith("Release") && name != requireReleaseSigning.name) dependsOn(requireReleaseSigning)
}
tasks.named("preBuild").configure { dependsOn(buildAndroidRust) }

flutter { source = "../.." }
