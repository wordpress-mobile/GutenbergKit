plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.jetbrains.kotlin.android)
    alias(libs.plugins.jetbrains.kotlin.serialization)
    id("com.automattic.android.publish-to-s3")
    id("kotlin-parcelize")
}

android {
    namespace = "org.wordpress.gutenberg"
    compileSdk = 34

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 24

        buildConfigField(
            "String",
            "GUTENBERG_EDITOR_URL",
            "\"${rootProject.ext["gutenbergEditorUrl"] ?: ""}\""
        )

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("androidTest") {
            // Make shared test fixtures available as assets for instrumented tests.
            assets.srcDir(rootProject.file("../test-fixtures"))
        }
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            all {
                // Make the shared test fixtures available to fixture-driven tests.
                val fixturesDir = rootProject.file("../test-fixtures/http")
                it.systemProperty("test.fixtures.dir", fixturesDir.absolutePath)
                // Track fixture files as task inputs so changes trigger re-runs.
                it.inputs.dir(fixturesDir)
            }
        }
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.webkit)
    implementation(libs.gson)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.jsoup)
    implementation(libs.okhttp)

    testImplementation(libs.junit)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockito.core)
    testImplementation(libs.mockito.kotlin)
    testImplementation(libs.robolectric)
    testImplementation(libs.okhttp.mockwebserver)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}

project.afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("maven") {
                from(components["release"])

                groupId = "org.wordpress.gutenbergkit"
                artifactId = "android"
                // version is set by 'publish-to-s3' plugin
            }
        }
    }
}
