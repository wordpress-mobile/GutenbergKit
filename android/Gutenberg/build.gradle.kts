plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.jetbrains.kotlin.compose)
    alias(libs.plugins.jetbrains.kotlin.parcelize)
    alias(libs.plugins.jetbrains.kotlin.serialization)
    id("com.automattic.android.publish-to-s3")
}

val generateSupportedLocales = tasks.register<GenerateSupportedLocales>("generateSupportedLocales") {
    description = "Generates SupportedLocales.kt from the shipped translation manifest."
    group = "build"

    manifest.from(layout.projectDirectory.file("src/main/assets/supported-locales.json"))
}

androidComponents.onVariants { variant ->
    val kotlinSources = checkNotNull(variant.sources.kotlin) {
        "Variant ${variant.name} has no Kotlin sources to add SupportedLocales to"
    }
    kotlinSources.addGeneratedSourceDirectory(
        generateSupportedLocales,
        GenerateSupportedLocales::outputDirectory,
    )

    // Make shared test fixtures available as assets for instrumented tests.
    variant.androidTest?.sources?.assets?.addStaticSourceDirectory(
        rootProject.file("../test-fixtures").absolutePath
    )
}

android {
    namespace = "org.wordpress.gutenberg"
    compileSdk = 34
    resourcePrefix = "gbk_"

    // Declared here rather than left to `publish-to-s3`, which looks the
    // extension up as the legacy `com.android.build.gradle.LibraryExtension`.
    // AGP 9's new DSL no longer registers that type, so the plugin's own
    // `singleVariant` call silently no-ops and the `release` component is
    // never created. Remove this when upgrading to a plugin release that fixes
    // Automattic/publish-to-s3-gradle-plugin#42: AGP rejects declaring the
    // same variant twice, so keeping both breaks configuration.
    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    defaultConfig {
        minSdk = 24

        buildConfigField(
            "String",
            "GUTENBERG_EDITOR_URL",
            "\"${rootProject.ext["gutenbergEditorUrl"] ?: ""}\""
        )

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        configureBuildkiteTestCollector(
            testInstrumentationRunnerArguments,
            "BUILDKITE_ANALYTICS_TOKEN_ANDROID_LIBRARY_E2E",
        )

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
        sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.java.get())
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
    implementation(libs.androidsvg)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.activity.compose)

    testImplementation(libs.json)
    testImplementation(libs.junit)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockito.core)
    testImplementation(libs.mockito.kotlin)
    testImplementation(libs.robolectric)
    testImplementation(libs.okhttp.mockwebserver)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.buildkite.test.collector.instrumented)
    androidTestImplementation(kotlin("test"))
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
