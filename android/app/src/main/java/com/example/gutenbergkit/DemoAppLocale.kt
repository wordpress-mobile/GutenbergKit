package com.example.gutenbergkit

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import java.util.Locale

/**
 * Reads the language the demo app is running in, so the editor can be told
 * which translations to load.
 *
 * The language is chosen through the system's per-app language picker
 * (Settings > Apps > GutenbergKit > Language), which offers the locales
 * declared in `res/xml/locales_config.xml`. Forwarding it to
 * `EditorConfiguration` lets the editor's localization — including
 * right-to-left rendering — be exercised without code changes.
 *
 * Unlike the iOS demo app, no resolution logic lives here:
 * `EditorConfiguration.Builder.setLocale(Locale)` already resolves against the
 * bundled translations via the library's `LocaleResolver`.
 */
object DemoAppLocale {

    /**
     * The locale to hand the editor.
     *
     * Reads the platform's [LocaleManager] directly rather than going through
     * `AppCompatDelegate.getApplicationLocales()`. That helper resolves the
     * application locale by walking appcompat's registry of live activity
     * delegates, and every activity in this app extends `ComponentActivity`
     * rather than `AppCompatActivity`, so the registry is always empty and the
     * helper reports no selection regardless of what the system holds.
     *
     * Falls back to the device language when no per-app language is set, or on
     * Android versions predating per-app languages (API < 33).
     */
    fun current(context: Context): Locale {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return Locale.getDefault()
        }

        val locales = context.getSystemService(LocaleManager::class.java)
            ?.applicationLocales

        if (locales == null || locales.isEmpty) {
            return Locale.getDefault()
        }
        return locales[0]
    }
}
