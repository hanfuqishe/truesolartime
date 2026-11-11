import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// 鍙戝竷绛惧悕淇℃伅鏀惧湪浠撳簱澶栫殑 keystore.properties 涓紝閬垮厤绉侀挜杩涘叆鐗堟湰搴撱€?
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// 高德逆地理编码用的 key（Android 平台 Key，绑定包名 + 签名 SHA1），同样放在仓库外。
val amapProperties = Properties().apply {
    val file = rootProject.file("amap.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val amapApiKey = amapProperties.getProperty("apiKey", amapProperties.getProperty("webKey", ""))

android {
    namespace = "com.realsuntime.solartime"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.realsuntime.solartime"
        minSdk = 24
        targetSdk = 35
        versionCode = 15
        versionName = "1.4.8"
        buildConfigField("String", "AMAP_API_KEY", "\"$amapApiKey\"")
        manifestPlaceholders["amapApiKey"] = amapApiKey
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("org.osmdroid:osmdroid-android:6.1.20")
    implementation("com.amap.api:search:9.7.1")
    debugImplementation("androidx.compose.ui:ui-tooling")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

/**
 * 每次 assembleRelease 之后，把 APK 另存一份为「真太阳时-<版本号>.apk」放到仓库根的 dist/，
 * 免去手工改名；dist/ 不入库（.gitignore 已忽略 *.apk）。
 */
val releaseApkName = "真太阳时-${android.defaultConfig.versionName}.apk"

tasks.register<Copy>("renameReleaseApk") {
    group = "build"
    description = "把 release APK 复制为「真太阳时-<版本号>.apk」"
    from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
    into(rootProject.layout.projectDirectory.dir("dist"))
    rename { releaseApkName }
    onlyIf { layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile.exists() }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy("renameReleaseApk")
}
