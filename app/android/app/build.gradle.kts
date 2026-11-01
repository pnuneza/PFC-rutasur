plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma propia de RutaSur. Se lee de app/android/key.properties (en la PC) o de las
// variables de entorno que GitHub Actions arma con sus secretos. Sin ellas, se firma con
// la clave de depuración, que cambia en cada máquina y obliga a desinstalar para actualizar.
val propiedadesFirma = java.util.Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}

fun datoFirma(propiedad: String, variable: String): String? =
    propiedadesFirma.getProperty(propiedad) ?: System.getenv(variable)?.takeIf { it.isNotBlank() }

val almacenFirma = datoFirma("storeFile", "RUTASUR_KEYSTORE")
val claveFirma = datoFirma("storePassword", "RUTASUR_KEYSTORE_PASSWORD")
val hayFirmaPropia = almacenFirma != null && claveFirma != null

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

    signingConfigs {
        if (hayFirmaPropia) {
            create("rutasur") {
                storeFile = file(almacenFirma!!)
                storePassword = claveFirma
                keyAlias = datoFirma("keyAlias", "RUTASUR_KEY_ALIAS") ?: "rutasur"
                // En un almacén PKCS12 (el de keytool) la clave usa la misma contraseña
                keyPassword = datoFirma("keyPassword", "RUTASUR_KEY_PASSWORD") ?: claveFirma
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hayFirmaPropia) "rutasur" else "debug")
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
