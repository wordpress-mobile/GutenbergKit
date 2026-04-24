plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.jetbrains.kotlin.android)
    alias(libs.plugins.jetbrains.kotlin.compose)
}

// Read wp-env credentials at build time. The emulator cannot access host
// filesystem paths at runtime, so we bake the values into BuildConfig.
@Suppress("UNCHECKED_CAST")
val wpEnvCredentials: Map<String, String> = run {
    val file = rootProject.file("../.wp-env.credentials.json")
    if (file.exists()) {
        try {
            groovy.json.JsonSlurper().parseText(file.readText()) as Map<String, String>
        } catch (_: Exception) {
            emptyMap()
        }
    } else {
        emptyMap()
    }
}

android {
    namespace = "com.example.gutenbergkit"
    compileSdk = 34

    // Copy shared OAuth credentials into Android assets so they're available at runtime.
    // Only registered when the file exists — the app handles the missing-file case gracefully.
    val oauthCredentialsFile = rootProject.file("../wp_com_oauth_credentials.json")
    if (oauthCredentialsFile.exists()) {
        val copyOAuthCredentials by tasks.registering(Copy::class) {
            from(oauthCredentialsFile)
            into(layout.buildDirectory.dir("generated/oauth-assets"))
        }

        sourceSets["main"].assets.srcDir(copyOAuthCredentials.map { it.destinationDir })

        applicationVariants.configureEach {
            mergeAssetsProvider.configure {
                dependsOn(copyOAuthCredentials)
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.gutenbergkit"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Buildkite Test Engine: upload per-test results when a token is present in the env.
        // Absent locally → no listener is registered and the collector is fully inert.
        // Build metadata env vars are forwarded so uploaded results link back to the CI job:
        // https://github.com/buildkite/test-collector-android/blob/main/CI_CONFIGURATION.md#buildkite
        System.getenv("BUILDKITE_ANALYTICS_TOKEN_ANDROID_E2E")?.takeIf { it.isNotBlank() }?.let { token ->
            testInstrumentationRunnerArguments["listener"] =
                "com.buildkite.test.collector.android.InstrumentedTestCollector"
            testInstrumentationRunnerArguments["BUILDKITE_ANALYTICS_TOKEN"] = token

            listOf(
                "BUILDKITE_BUILD_ID",
                "BUILDKITE_BUILD_URL",
                "BUILDKITE_BRANCH",
                "BUILDKITE_COMMIT",
                "BUILDKITE_BUILD_NUMBER",
                "BUILDKITE_JOB_ID",
                "BUILDKITE_MESSAGE",
            ).forEach { key ->
                System.getenv(key)?.let { value -> testInstrumentationRunnerArguments[key] = value }
            }
        }

        buildConfigField("String", "WP_ENV_SITE_URL", "\"${wpEnvCredentials["siteUrl"] ?: ""}\"")
        buildConfigField("String", "WP_ENV_SITE_API_ROOT", "\"${wpEnvCredentials["siteApiRoot"] ?: ""}\"")
        buildConfigField("String", "WP_ENV_AUTH_HEADER", "\"${wpEnvCredentials["authHeader"] ?: ""}\"")
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
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.recyclerview)
    implementation(libs.wordpress.rs.android)
    implementation(libs.okhttp)
    implementation(project(":Gutenberg"))

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.activity.compose)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.espresso.web)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.buildkite.test.collector.instrumented)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
