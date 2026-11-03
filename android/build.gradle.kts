// Top-level build file where you can add configuration options common to all sub-projects/modules.
val localProperties = java.util.Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

// A `-P` property overrides local.properties, so `make` targets can choose the
// editor source explicitly. Null when neither sets it; an empty value selects
// the bundled editor.
val gutenbergEditorUrl = ((findProperty("GUTENBERG_EDITOR_URL") as String?)
    ?: localProperties.getProperty("GUTENBERG_EDITOR_URL"))?.trim()

ext {
    set("gutenbergEditorUrl", gutenbergEditorUrl)
}

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    // Pins the Kotlin Gradle plugin for the whole build. AGP 9 bundles its own
    // (older) copy, whose Parcelize sub-plugin only recognises the legacy
    // `BaseExtension` DSL and so silently skips AGP 9 projects.
    alias(libs.plugins.jetbrains.kotlin.compose) apply false
    alias(libs.plugins.jetbrains.kotlin.parcelize) apply false
    alias(libs.plugins.jetbrains.kotlin.serialization) apply false
    alias(libs.plugins.detekt) apply false
}

subprojects {
    apply(plugin = "io.gitlab.arturbosch.detekt")

    configure<io.gitlab.arturbosch.detekt.extensions.DetektExtension> {
        config.setFrom(rootProject.files("detekt.yml"))
        buildUponDefaultConfig = true
        baseline = file("detekt-baseline.xml")
    }
}
