import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play upload signing — local only (never commit key.properties / *.jks).
// Place android/key.properties next to this module's parent (android/).
// See android/key.properties.example.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists().also { exists ->
    if (exists) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }
}

fun requireReleaseSigningConfigured() {
    if (!hasReleaseKeystore) {
        throw GradleException(
            """
            |Release signing is not configured.
            |Copy android/key.properties.example → android/key.properties,
            |create an upload keystore, and set storeFile / passwords / keyAlias.
            |Debug signing is NEVER used for release (Play Store).
            |See android/key.properties.example for steps.
            """.trimMargin(),
        )
    }
    val alias = (keystoreProperties["keyAlias"] as String?)?.trim().orEmpty()
    val keyPassword = (keystoreProperties["keyPassword"] as String?)?.trim().orEmpty()
    val storePassword = (keystoreProperties["storePassword"] as String?)?.trim().orEmpty()
    val storeFilePath = (keystoreProperties["storeFile"] as String?)?.trim().orEmpty()
    if (alias.isEmpty() ||
        keyPassword.isEmpty() ||
        storePassword.isEmpty() ||
        storeFilePath.isEmpty()
    ) {
        throw GradleException(
            "android/key.properties is incomplete. " +
                "Required: storePassword, keyPassword, keyAlias, storeFile.",
        )
    }
    if (storePassword.startsWith("YOUR_") ||
        keyPassword.startsWith("YOUR_") ||
        alias == "YOUR_KEY_ALIAS"
    ) {
        throw GradleException(
            "android/key.properties still has placeholder values. " +
                "Replace YOUR_* with real secrets (do not commit that file).",
        )
    }
    // storeFile path is relative to android/app/ (this module).
    val store = file(storeFilePath)
    if (!store.isFile) {
        throw GradleException(
            "Release keystore not found: ${store.absolutePath} " +
                "(storeFile=$storeFilePath relative to android/app/).",
        )
    }
}

android {
    namespace = "com.cafein.cafein"
    // AdMob quick-start: compileSdk 35+ (Flutter default is currently higher).
    compileSdk = maxOf(35, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cafein.cafein"
        // AdMob / google_mobile_ads 9.x: minSdk 24+.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        // Only register release signing when a real key.properties is present.
        // Never fall back to signingConfigs.getByName("debug").
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                // storeFile path is relative to android/app/ (this module).
                storeFile = file(keystoreProperties["storeFile"] as String)
            }
        }
    }

    buildTypes {
        release {
            // Play Store AAB/APK must use the upload keystore — never debug.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // If key.properties is missing, leave unsigned here and fail
            // assembleRelease / bundleRelease in afterEvaluate (below).
        }
    }
}

// Fail release package tasks early when signing is missing / invalid.
afterEvaluate {
    tasks.matching { task ->
        val n = task.name
        n == "assembleRelease" ||
            n == "bundleRelease" ||
            n == "assembleReleaseUnitTest" ||
            (n.startsWith("bundle") && n.endsWith("Release"))
    }.configureEach {
        doFirst {
            requireReleaseSigningConfigured()
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
    // Google Mobile Ads SDK — matches google_mobile_ads 9.x / AdMob quick-start.
    // https://developers.android.com/admob/android/quick-start
    implementation("com.google.android.gms:play-services-ads:25.4.0")
}
