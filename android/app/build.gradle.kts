import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val keystoreProperties = Properties().apply {
    val propertiesFile = rootProject.file("keystore.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use { load(it) }
    }
}

fun readSecret(name: String): String? {
    val envValue = System.getenv(name)
    if (!envValue.isNullOrBlank()) return envValue
    val propValue = keystoreProperties.getProperty(name)
    return if (propValue.isNullOrBlank()) null else propValue
}

val releaseKeystorePath = readSecret("ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword = readSecret("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = readSecret("ANDROID_KEY_ALIAS")
val releaseKeyPassword = readSecret("ANDROID_KEY_PASSWORD")

val hasReleaseSigning =
    !releaseKeystorePath.isNullOrBlank() &&
    rootProject.file(releaseKeystorePath).exists() &&
    !releaseKeystorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.drizzle.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.drizzle.app"
        minSdk = 24
        targetSdk = 35
        // versionCode tracks the sequential build count N (the integer part of
        // CFBundleVersion's N.WAIS scheme; see .github/copilot-instructions.md).
        versionCode = 3
        versionName = "2.1.0"
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = rootProject.file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Fallback for local side-loading without Play signing secrets
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.webkit:webkit:1.12.1")
}
