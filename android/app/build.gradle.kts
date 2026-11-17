import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload signing (Plan 6 decision 12). android/key.properties is git-ignored and names a
// keystore outside the repo. Without it a release is debug-signed, which Play refuses.
val uploadKey = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
// A file that is there but incomplete stops the build and names the missing entries, never a value.
val uploadKeyGaps = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .filter { uploadKey.getProperty(it).isNullOrBlank() }
if (!uploadKey.isEmpty && uploadKeyGaps.isNotEmpty()) {
    throw GradleException("android/key.properties has no value for: ${uploadKeyGaps.joinToString()}")
}

android {
    namespace = "io.github.fifothehein.tminus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.fifothehein.tminus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged manifest, R.color tokens and drawables.
            isIncludeAndroidResources = true
        }
    }

    signingConfigs {
        if (!uploadKey.isEmpty) create("upload") {
            storeFile = file(uploadKey.getProperty("storeFile"))
            storePassword = uploadKey.getProperty("storePassword")
            keyAlias = uploadKey.getProperty("keyAlias")
            keyPassword = uploadKey.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadKey.isEmpty) {
                // The debug key keeps `flutter run --release` working. Say so only when a release is asked
                // for, so debug builds and unit tests stay quiet. `flutter build` runs Gradle with -q, which
                // hides warnings, so the message is logged at the quiet level.
                if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
                    logger.quiet("android/key.properties is missing: the release build is debug-signed and Play will refuse it.")
                }
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("upload")
            }
            // Native debug symbols go into the bundle, so Play can symbolicate native crashes (decision 14).
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
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
    // Checked on Google Maven / Maven Central, 2026-10-06. Compose BOM 2026.06.01 (Compose 1.11.4)
    // is the newest that compiles against compileSdk 36: BOM 2026.08.00+ and androidx.core 1.19.x
    // declare minCompileSdk=37. activity-compose 1.13.0 pulls core-ktx 1.18.0 itself.
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    // Plan 4 (checked on Google Maven, 2026-10-08): WorkManager 2.12.0 declares minCompileSdk=35;
    // concurrent-futures gives SyncWorker CallbackToFutureAdapter without coroutines of our own.
    implementation("androidx.work:work-runtime:2.12.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.work:work-testing:2.12.0")
    androidTestImplementation("androidx.test.ext:junit-ktx:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}

// With isIncludeAndroidResources, the unit-test package reads the merged assets folder that
// Flutter's copyFlutterAssets<Variant> also writes. Gradle 9 rejects that undeclared dependency.
tasks.configureEach {
    val variant = Regex("package(\\w+)UnitTestForUnitTest").matchEntire(name)?.groupValues?.get(1)
    if (variant != null) dependsOn("copyFlutterAssets$variant")
}
