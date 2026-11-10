import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.lumtub.lumtub"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.lumtub.lumtub"
        // Android 7: many TVs sold in China still run 7 to 9.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The release key comes from android/key.properties, which CI writes
    // from the repository secrets. Without it the debug key signs, so a
    // pull request build still installs; such an APK cannot update one
    // signed with the release key.
    val keyFile = rootProject.file("key.properties")
    val release = keyFile.exists()
    signingConfigs {
        if (release) {
            val keys = Properties().apply { keyFile.inputStream().use { load(it) } }
            create("release") {
                storeFile = rootProject.file(keys.getProperty("storeFile"))
                storePassword = keys.getProperty("storePassword")
                keyAlias = keys.getProperty("keyAlias")
                keyPassword = keys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (release) "release" else "debug")
            proguardFiles("proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            // Unpacked at install: yt-dlp's Python (libpython.so) is started
            // as a program, which Android allows only from the app's
            // library folder on disk.
            useLegacyPackaging = true
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
    implementation("androidx.annotation:annotation:1.11.0")
    // Only its Python, QuickJS and yt-dlp files are used
    // (PythonSetup.kt); its Kotlin and the libraries that needs are not.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1") { isTransitive = false }
    // Must be the version of the rustls-platform-verifier-android crate in
    // native/lumtub_core/Cargo.lock (checked by android/packaging/build-core.sh).
    implementation("org.rustls:rustls-platform-verifier:0.2.0")
}
