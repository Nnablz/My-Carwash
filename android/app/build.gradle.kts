import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeyPropertiesFile = keystorePropertiesFile.exists()
if (hasKeyPropertiesFile) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val releaseStoreFilePath = keystoreProperties.getProperty("storeFile")?.trim().orEmpty()
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")?.trim().orEmpty()
val releaseStorePassword = keystoreProperties.getProperty("storePassword")?.trim().orEmpty()
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")?.trim().orEmpty()
val releaseStoreFile = if (releaseStoreFilePath.isNotEmpty()) file(releaseStoreFilePath) else null
val hasReleaseSigning =
    hasKeyPropertiesFile &&
        releaseStoreFile != null &&
        releaseStoreFile.exists() &&
        releaseKeyAlias.isNotEmpty() &&
        releaseStorePassword.isNotEmpty() &&
        releaseKeyPassword.isNotEmpty()

val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as? String)
    ?.split(",")
    ?.mapNotNull { encoded ->
        val decoded = runCatching {
            String(Base64.getDecoder().decode(encoded.trim()), Charsets.UTF_8)
        }.getOrNull() ?: return@mapNotNull null
        val separatorIndex = decoded.indexOf('=')
        if (separatorIndex <= 0) {
            null
        } else {
            decoded.substring(0, separatorIndex) to decoded.substring(separatorIndex + 1)
        }
    }
    ?.toMap()
    ?: emptyMap()

val appEnv = (
    (project.findProperty("appEnv") as? String)
        ?: (project.findProperty("APP_ENV") as? String)
        ?: dartDefines["APP_ENV"]
        ?: "dev"
    ).trim().lowercase()

val resolvedAppName = when (appEnv) {
    "prod", "production" -> "ClearWash POS"
    "staging" -> "ClearWash POS (Staging)"
    else -> "ClearWash POS (Dev)"
}

android {
    namespace = "com.protein.protein"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.protein.protein"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        resValue("string", "app_name", resolvedAppName)
        resValue("string", "app_env", appEnv)
    }

    buildFeatures {
        resValues = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
