package com.example.gutenbergkit

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/**
 * JUnit rule that disables device animations before each test and
 * restores the original values afterward.
 *
 * Unlike `testOptions { animationsDisabled = true }` in Gradle, this
 * approach does not permanently alter emulator settings — animations
 * are restored in the `finally` block even if the test fails.
 */
class DisableAnimationsRule : TestRule {

    private companion object {
        val ANIMATION_SETTINGS = listOf(
            "window_animation_scale",
            "transition_animation_scale",
            "animator_duration_scale"
        )
    }

    override fun apply(base: Statement, description: Description): Statement {
        return object : Statement() {
            override fun evaluate() {
                val uiAutomation = InstrumentationRegistry
                    .getInstrumentation()
                    .uiAutomation

                val originalValues = ANIMATION_SETTINGS.map { setting ->
                    val value = executeShellCommand(uiAutomation, "settings get global $setting")
                    // Default to 1.0 when the setting doesn't exist on the device
                    // (adb returns the string "null" for missing settings).
                    setting to if (value == "null") "1.0" else value
                }

                try {
                    for (setting in ANIMATION_SETTINGS) {
                        executeShellCommand(uiAutomation, "settings put global $setting 0")
                    }
                    base.evaluate()
                } finally {
                    for ((setting, value) in originalValues) {
                        executeShellCommand(uiAutomation, "settings put global $setting $value")
                    }
                }
            }
        }
    }

    private fun executeShellCommand(
        uiAutomation: android.app.UiAutomation,
        command: String
    ): String {
        val pfd: ParcelFileDescriptor = uiAutomation.executeShellCommand(command)
        return pfd.use {
            ParcelFileDescriptor.AutoCloseInputStream(it)
                .bufferedReader()
                .readText()
                .trim()
        }
    }
}
