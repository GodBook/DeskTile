import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.isFile) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

val releaseStoreFile =
    keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
val releaseSigningReady =
    releaseStoreFile?.isFile == true &&
        listOf("storePassword", "keyAlias", "keyPassword").all {
            !keystoreProperties.getProperty(it).isNullOrBlank()
        }

android {
    namespace = "com.desktile.desktile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // This identifier is the app's permanent Play Store identity.
        applicationId = "com.desktile.desktile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Glance widgets use Compose at compile time. Kotlin 2.4's Compose
    // compiler is supplied by the Kotlin Compose plugin above.
    buildFeatures {
        compose = true
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 应用内 APK 更新通过 AndroidX FileProvider 共享缓存中的安装包。
    implementation("androidx.core:core:1.13.1")
    // home_widget 0.9.3 brings this transitively, but declaring it here keeps
    // the app's Glance source independent of a plugin implementation detail.
    implementation("androidx.glance:glance-appwidget:1.1.1")
}

tasks.configureEach {
    val packagesRelease =
        name.contains("Release", ignoreCase = true) &&
            (name.startsWith("assemble", ignoreCase = true) ||
                name.startsWith("bundle", ignoreCase = true) ||
                name.startsWith("package", ignoreCase = true))
    if (packagesRelease) {
        doFirst {
            if (!releaseSigningReady) {
                throw GradleException(
                    "Release signing is not configured. Copy android/key.properties.example " +
                        "to android/key.properties and provide the release keystore.",
                )
            }
        }
    }
}
