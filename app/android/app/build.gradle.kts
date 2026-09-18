import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de publication.
//
// Le fichier `key.properties` et le keystore ne sont JAMAIS versionnes (voir
// .gitignore). En leur absence — poste de developpement, integration continue
// sans secrets configures — la compilation retombe sur la cle de debogage, ce
// qui permet de produire une APK testable sans jamais publier par erreur.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "io.github.axox934.assiette"

    // Valeurs fournies par Flutter 3.47.4 : compileSdk 36, targetSdk 36, minSdk 24.
    // On les laisse pilotees par le SDK plutot que figees en dur, pour ne pas
    // deriver lors des montees de version de Flutter.
    //
    // targetSdk 36 (Android 16) est le minimum impose par Google Play depuis le
    // 31 aout 2026 pour toute nouvelle application.
    compileSdk = flutter.compileSdkVersion

    // Le NDK est obligatoire, et cette ligne le dit.
    //
    // `path_provider_android` depend de `jni`, qui compile du C++ par CMake et
    // produit `libdartjni.so` pour chaque architecture. Sans NDK, la compilation
    // s'arrete sur « Android sdkmanager did not install NDK » : laisser cette
    // ligne absente ne l'evite donc pas, Flutter applique sa propre valeur par
    // defaut et reclame le meme paquet.
    //
    // On reprend `flutter.ndkVersion` plutot que d'ecrire la version en clair :
    // une seule source de verite, qui suit les montees de version de Flutter.
    // Flutter 3.47.4 exige 28.2.13676358.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Exige par flutter_local_notifications : la programmation de
        // notifications s'appuie sur des API Java 8+ (java.time) que le
        // « desugaring » rend disponibles sur les anciens Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "io.github.axox934.assiette"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // APK installable pour les tests, non publiable sur le Play Store.
                signingConfigs.getByName("debug")
            }

            // Minification et reduction de ressources laissees desactivees :
            // plusieurs greffons (lecteur de code-barres, notifications) passent
            // par de la reflexion et exigeraient des regles ProGuard ecrites a la
            // main. La fiabilite prime ici sur quelques megaoctets gagnes.
            isMinifyEnabled = false
            isShrinkResources = false
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
    // Bibliotheque de desugaring, requise par flutter_local_notifications.
    // Version 2.x : la branche 1.2.x du greffon ne convient qu'aux anciens AGP.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
