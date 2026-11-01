plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pe.edu.ucsm.rutasur"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "pe.edu.ucsm.rutasur"
        // flutter_secure_storage necesita Android 6.0 (API 23) o superior
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Dos aplicaciones sobre el mismo código (P05 Tabla 32): se instalan una al lado de la
    // otra y solo la del conductor declara los permisos de ubicación en segundo plano
    // (src/conductor/AndroidManifest.xml).
    //   flutter build apk --flavor pasajero  -t lib/entrypoints/main_pasajero.dart
    //   flutter build apk --flavor conductor -t lib/entrypoints/main_conductor.dart
    flavorDimensions += "app"
    productFlavors {
        create("pasajero") {
            dimension = "app"
            manifestPlaceholders["nombreApp"] = "RutaSur"
        }
        create("conductor") {
            dimension = "app"
            applicationIdSuffix = ".conductor"
            manifestPlaceholders["nombreApp"] = "RutaSur Conductor"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
